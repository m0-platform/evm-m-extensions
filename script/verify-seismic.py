#!/usr/bin/env python3
"""
Auto-verify every contract from a Seismic (mercury/ssolc) deploy broadcast.

Forge can't verify mercury builds (the explorer rejects `evmVersion: mercury` and wants the
compiler labelled `v0.8.31+commit.cd9163d8`), so this rebuilds the exact ssolc standard-json
from out/build-info (closure only, evmVersion dropped), matches each deployed address by
creation bytecode, derives constructor args from the init code, and POSTs verifysourcecode.
Needs python3 + jq and FULL build-info (`build_info = true`), fresh from the deploy build.

USAGE
    python3 script/verify-seismic.py <DeployScript.s.sol> <chain_id> [--dry-run]
    python3 script/verify-seismic.py --run <path/to/run-*.json> [--dry-run]

ENV
    VERIFIER_URL        full explorer verify endpoint (required unless --dry-run)
    VERIFIER_API_KEY    defaults to "abc" (testnet placeholder)
"""
import glob
import json
import os
import re
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BUILD_INFO_GLOB = os.path.join(ROOT, "out", "build-info", "*.json")


def strip0x(h):
    return h[2:] if h and h.startswith("0x") else (h or "")


def jq(args, path):
    r = subprocess.run(["jq", *args, path], capture_output=True, text=True)
    if r.returncode != 0:
        raise RuntimeError(f"jq failed on {os.path.basename(path)}: {r.stderr.strip()[:300]}")
    return r.stdout


def newest_run(script_name, chain_id):
    d = os.path.join(ROOT, "broadcast", script_name, str(chain_id))
    runs = [f for f in glob.glob(os.path.join(d, "run-*.json"))]
    if not runs:
        sys.exit(f"no broadcast runs under {d}")
    return max(runs, key=os.path.getmtime)


def collect_targets(run):
    """Return list of (address, initcode_no0x) for every deployed contract."""
    out = []
    for tx in run.get("transactions", []):
        if tx.get("transactionType") == "CREATE" and tx.get("contractAddress"):
            t = tx.get("transaction", {})
            ic = strip0x(t.get("input") or t.get("data") or "")
            if ic:
                out.append((tx["contractAddress"], ic))
        for ac in tx.get("additionalContracts") or []:
            if ac.get("transactionType") in ("CREATE", "CREATE2") and ac.get("initCode"):
                out.append((ac["address"], strip0x(ac["initCode"])))
    # de-dupe by address, keep first
    seen, uniq = set(), []
    for a, ic in out:
        k = a.lower()
        if k not in seen:
            seen.add(k)
            uniq.append((a, ic))
    return uniq


# jq: for the init codes in $ics (slurped from a file), emit every
# (ic, path, name, obj) where a compiled creation object is a prefix of an init
# code. One pass per build-info file; the prefix check runs inside jq so only
# tiny match records cross the boundary. `// {}` guards build-infos with no
# compiled contracts (e.g. script-only or lean build-info units).
MATCH_FILTER = r"""
[ (.output.contracts // {}) | to_entries[] as $p | $p.value | to_entries[]
  | select((.value.evm.bytecode.object // "") | length > 0)
  | {path:$p.key, name:.key, obj:.value.evm.bytecode.object} ] as $c
| [ $ics[] as $ic | $c[] as $e | select($ic | startswith($e.obj))
    | {ic:$ic, path:$e.path, name:$e.name, obj:$e.obj} ]
"""


def find_matches(targets):
    """Map address -> {build_info, path, name, obj} via longest bytecode-prefix match."""
    import tempfile
    ic_to_addr = {ic: a for a, ic in targets}
    # init codes can total >ARG_MAX for a big stack, so feed them via a file.
    with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as f:
        f.write("\n".join(json.dumps(ic) for _, ic in targets))
        ics_file = f.name
    candidates = {}  # addr -> best match (longest obj)
    try:
        for bi in sorted(glob.glob(BUILD_INFO_GLOB)):
            out = jq(["-c", "--slurpfile", "ics", ics_file, MATCH_FILTER], bi)
            for m in json.loads(out):
                addr = ic_to_addr.get(m["ic"])
                if not addr:
                    continue
                prev = candidates.get(addr)
                if prev is None or len(m["obj"]) > len(prev["obj"]):
                    candidates[addr] = {"bi": bi, "path": m["path"], "name": m["name"], "obj": m["obj"]}
    finally:
        os.unlink(ics_file)
    return candidates


def etherscan_version(meta_version):
    """0.8.31-develop.2026.4.29+commit.cd9163d8  ->  v0.8.31+commit.cd9163d8"""
    m = re.match(r"^(\d+\.\d+\.\d+).*\+commit\.([0-9a-fA-F]+)", meta_version)
    if not m:
        sys.exit(f"cannot parse compiler version: {meta_version}")
    return f"v{m.group(1)}+commit.{m.group(2)}"


# jq: pull the contract metadata (string) — carries closure keys, compiler
# version, and optimizer settings.
META_FILTER = '.output.contracts[$p][$n].metadata'

# jq: build the minimal standard-json input (closure sources + settings, no
# evmVersion, compact outputSelection). Bytecode/metadata-affecting settings
# (optimizer, viaIR, remappings, metadata) are preserved verbatim from build-info.
INPUT_FILTER = r"""
{ language: "Solidity",
  sources: (.input.sources | to_entries | map(select(.key as $k | ($keys | index($k)))) | from_entries),
  settings: ( .input.settings
    | { optimizer, viaIR, metadata, remappings,
        outputSelection: {"*": {"*": ["abi","evm.bytecode","evm.deployedBytecode","metadata"], "": ["ast"]}} } ) }
"""


def build_payload(match, initcode):
    bi = match["bi"]
    path, name = match["path"], match["name"]
    meta = json.loads(jq(["-r", "--arg", "p", path, "--arg", "n", name, META_FILTER], bi))
    cv = etherscan_version(meta["compiler"]["version"])
    opt = meta.get("settings", {}).get("optimizer", {})
    runs = opt.get("runs", 200)
    opt_used = "1" if opt.get("enabled") else "0"
    closure = sorted(meta["sources"].keys())
    std_input = jq(["-c", "--argjson", "keys", json.dumps(closure), INPUT_FILTER], bi)
    ctor_args = initcode[len(match["obj"]):]
    return {
        "contractname": f"{path}:{name}",
        "compilerversion": cv,
        "optimizationUsed": opt_used,
        "runs": str(runs),
        "constructorArguements": ctor_args,
        "sourceCode": std_input,
        "closure": len(closure),
    }


# The socialscan explorer 5xx's intermittently; treat these as retryable, incl.
# when wrapped in an HTTP 200 body (e.g. {"message":"...HTTP Error 503..."}).
_TRANSIENT_MARKERS = ("http error 5", "service unavailable", "bad gateway",
                      "gateway time-out", "gateway timeout", "timed out", "timeout")


def _is_transient(text):
    low = text.lower()
    return any(m in low for m in _TRANSIENT_MARKERS)


def submit(url, api_key, address, p, retries=None):
    if retries is None:
        retries = max(1, int(os.environ.get("VERIFY_RETRIES", "4")))
    data = urllib.parse.urlencode({
        "apikey": api_key,
        "module": "contract",
        "action": "verifysourcecode",
        "codeformat": "solidity-standard-json-input",
        "contractaddress": address,
        "contractname": p["contractname"],
        "compilerversion": p["compilerversion"],
        "optimizationUsed": p["optimizationUsed"],
        "runs": p["runs"],
        "constructorArguements": p["constructorArguements"],
        "sourceCode": p["sourceCode"],
    }).encode()
    for attempt in range(retries):
        last = attempt == retries - 1
        wait = 3 * (2 ** attempt)  # 3s, 6s, 12s, ...
        try:
            req = urllib.request.Request(url, data=data, method="POST")
            with urllib.request.urlopen(req, timeout=180) as r:
                body = json.loads(r.read().decode())
        except urllib.error.HTTPError as e:
            if e.code >= 500 and not last:
                print(f"      {address}: HTTP {e.code}, retry in {wait}s ({attempt + 1}/{retries - 1})")
                time.sleep(wait)
                continue
            raise
        except urllib.error.URLError as e:  # connection reset / DNS / timeout
            if not last:
                print(f"      {address}: {e.reason}, retry in {wait}s ({attempt + 1}/{retries - 1})")
                time.sleep(wait)
                continue
            raise
        # HTTP 200, but the explorer may have wrapped a transient 5xx in the body.
        if not last and _is_transient(str(body.get("message", ""))):
            print(f"      {address}: transient explorer error, retry in {wait}s ({attempt + 1}/{retries - 1})")
            time.sleep(wait)
            continue
        return body
    return body


def main():
    argv = sys.argv[1:]
    dry = "--dry-run" in argv
    argv = [a for a in argv if a != "--dry-run"]
    if argv and argv[0] == "--run":
        run_path = argv[1]
    elif len(argv) >= 2:
        run_path = newest_run(argv[0], argv[1])
    else:
        sys.exit(__doc__)

    url = os.environ.get("VERIFIER_URL")
    api_key = os.environ.get("VERIFIER_API_KEY") or "abc"
    if not dry and not url:
        sys.exit("VERIFIER_URL not set (or pass --dry-run)")

    run = json.load(open(run_path))
    targets = collect_targets(run)
    print(f"broadcast: {os.path.relpath(run_path, ROOT)}")
    print(f"deployed contracts found: {len(targets)}")
    matches = find_matches(targets)

    rc = 0
    for addr, ic in targets:
        m = matches.get(addr)
        if not m:
            print(f"  SKIP  {addr}  (bytecode not in build-info — external/factory)")
            continue
        p = build_payload(m, ic)
        label = (f"{addr}  {p['contractname'].split(':')[-1]}  "
                 f"[{p['compilerversion']}, runs={p['runs']}, {p['closure']} srcs, "
                 f"args {len(p['constructorArguements'])//2}B]")
        if dry:
            print(f"  WOULD VERIFY  {label}")
            continue
        try:
            body = submit(url, api_key, addr, p)
        except Exception as e:  # noqa: BLE001
            print(f"  ERROR {addr}: {e}")
            rc = 1
            continue
        msg = str(body.get("message", body))
        ok = body.get("status") == "1" or "is verified" in msg or "already verified" in msg
        print(f"  {'OK  ' if ok else 'FAIL'}  {label}  -> {msg[:120]}")
        if not ok:
            rc = 1
        time.sleep(1)
    sys.exit(rc)


if __name__ == "__main__":
    main()

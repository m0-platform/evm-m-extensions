#!/usr/bin/env python3
"""Decrypt an encrypted Transfer(bytes)/Approval(bytes) payload emitted by MYieldToOne.

Reproduces the contract's emit pipeline off-chain (pure stdlib, no dependencies):
  1. ECDH    secp256k1(privkey, peer-pubkey) -> sha256(compressed shared point)   [libsecp256k1 convention]
  2. KDF #1  HKDF-SHA256(salt=none, info="aes-gcm key")        [inside precompile 0x65]
  3. KDF #2  HKDF-SHA256(salt=none, info="seismic_hkdf_105")   [precompile 0x68]
  4. nonce   first 12 bytes of keccak256(abi.encode(from, to, nonceCounter))
  5. AES-256-GCM decrypt (ciphertext || 16-byte tag)           [inverse of precompile 0x66]
ECDH is symmetric: pass either (recipient privkey + contract pubkey) or (contract privkey
+ recipient pubkey). The plaintext is abi.encode(uint256 amount).

USAGE
  decrypt-transfer-event.py --privkey <hex32> --peer-pubkey <hex33-compressed>
                            --from <address> --to <address> --ciphertext <hex>
                            (--nonce-counter <n> | --scan <max-n>)
  decrypt-transfer-event.py --self-test

  --privkey        decryption private key (recipient's, or the contract's)
  --peer-pubkey    the OTHER party's 33-byte compressed public key
  --from           event `from` topic (sender / approver) — bound into the nonce
  --to             event `to` topic (recipient / spender) — bound into the nonce
  --nonce-counter  the contract's encryptedEventNonce value used for this emit (1-based)
  --scan           try counters 1..max-n until the GCM tag verifies (when the counter is unknown)
  --ciphertext     event payload hex (ciphertext || 16-byte tag)
  --self-test      verify against vectors pinned from the Seismic precompiles (sforge mercury EVM)

Uses the 'cryptography' package for AES-GCM when installed; otherwise falls back to a
built-in pure-Python AES-GCM (validated against the same vectors).
"""

import argparse
import hashlib
import hmac
import sys

# ============ secp256k1 ============

P = 2**256 - 2**32 - 977
N = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141
GX = 0x79BE667EF9DCBBAC55A06295CE870B07029BFCDB2DCE28D959F2815B16F81798
GY = 0x483ADA7726A3C4655DA4FBFC0E1108A8FD17B448A68554199C47D08FFB10D4B8


def _point_add(a, b):
    if a is None:
        return b
    if b is None:
        return a
    (x1, y1), (x2, y2) = a, b
    if x1 == x2 and (y1 + y2) % P == 0:
        return None
    if a == b:
        lam = (3 * x1 * x1) * pow(2 * y1, P - 2, P) % P
    else:
        lam = (y2 - y1) * pow(x2 - x1, P - 2, P) % P
    x3 = (lam * lam - x1 - x2) % P
    return (x3, (lam * (x1 - x3) - y1) % P)


def _scalar_mult(k, point):
    result = None
    while k:
        if k & 1:
            result = _point_add(result, point)
        point = _point_add(point, point)
        k >>= 1
    return result


def decompress_pubkey(pub: bytes):
    if len(pub) != 33 or pub[0] not in (2, 3):
        raise ValueError("expected a 33-byte compressed public key")
    x = int.from_bytes(pub[1:], "big")
    y_sq = (pow(x, 3, P) + 7) % P
    y = pow(y_sq, (P + 1) // 4, P)
    if y * y % P != y_sq:
        raise ValueError("public key x-coordinate is not on secp256k1")
    if y % 2 != pub[0] % 2:
        y = P - y
    return (x, y)


def ecdh_shared_secret(privkey: bytes, peer_pubkey: bytes) -> bytes:
    """libsecp256k1 ECDH: sha256 of the compressed shared point."""
    k = int.from_bytes(privkey, "big")
    if not 0 < k < N:
        raise ValueError("private key out of range")
    x, y = _scalar_mult(k, decompress_pubkey(peer_pubkey))
    return hashlib.sha256(bytes([2 if y % 2 == 0 else 3]) + x.to_bytes(32, "big")).digest()


# ============ HKDF-SHA256 (RFC 5869) ============


def hkdf_sha256(ikm: bytes, info: bytes, length: int = 32) -> bytes:
    prk = hmac.new(b"\x00" * 32, ikm, hashlib.sha256).digest()
    okm, t, i = b"", b"", 1
    while len(okm) < length:
        t = hmac.new(prk, t + info + bytes([i]), hashlib.sha256).digest()
        okm += t
        i += 1
    return okm[:length]


def derive_aes_key(privkey: bytes, peer_pubkey: bytes) -> bytes:
    """Full key pipeline: ECDH -> HKDF("aes-gcm key") [0x65] -> HKDF("seismic_hkdf_105") [0x68]."""
    return hkdf_sha256(hkdf_sha256(ecdh_shared_secret(privkey, peer_pubkey), b"aes-gcm key"), b"seismic_hkdf_105")


# ============ keccak-256 (for the event nonce) ============

_KECCAK_RC = [
    0x0000000000000001, 0x0000000000008082, 0x800000000000808A, 0x8000000080008000,
    0x000000000000808B, 0x0000000080000001, 0x8000000080008081, 0x8000000000008009,
    0x000000000000008A, 0x0000000000000088, 0x0000000080008009, 0x000000008000000A,
    0x000000008000808B, 0x800000000000008B, 0x8000000000008089, 0x8000000000008003,
    0x8000000000008002, 0x8000000000000080, 0x000000000000800A, 0x800000008000000A,
    0x8000000080008081, 0x8000000000008080, 0x0000000080000001, 0x8000000080008008,
]
_KECCAK_ROT = [
    [0, 36, 3, 41, 18], [1, 44, 10, 45, 2], [62, 6, 43, 15, 61], [28, 55, 25, 21, 56], [27, 20, 39, 8, 14],
]
_M64 = (1 << 64) - 1


def _rol(v, s):
    return ((v << s) | (v >> (64 - s))) & _M64


def _keccak_f(state):
    for rc in _KECCAK_RC:
        c = [state[x][0] ^ state[x][1] ^ state[x][2] ^ state[x][3] ^ state[x][4] for x in range(5)]
        d = [c[(x - 1) % 5] ^ _rol(c[(x + 1) % 5], 1) for x in range(5)]
        state = [[state[x][y] ^ d[x] for y in range(5)] for x in range(5)]
        b = [[0] * 5 for _ in range(5)]
        for x in range(5):
            for y in range(5):
                b[y][(2 * x + 3 * y) % 5] = _rol(state[x][y], _KECCAK_ROT[x][y])
        state = [[b[x][y] ^ ((~b[(x + 1) % 5][y]) & b[(x + 2) % 5][y]) for y in range(5)] for x in range(5)]
        state[0][0] ^= rc
    return state


def keccak256(data: bytes) -> bytes:
    rate = 136
    data = data + b"\x01" + b"\x00" * (rate - len(data) % rate - 1)
    data = data[:-1] + bytes([data[-1] | 0x80])
    state = [[0] * 5 for _ in range(5)]
    for block in range(0, len(data), rate):
        for i in range(rate // 8):
            state[i % 5][i // 5] ^= int.from_bytes(data[block + 8 * i : block + 8 * i + 8], "little")
        state = _keccak_f(state)
    out = b""
    for i in range(4):
        out += state[i % 5][i // 5].to_bytes(8, "little")
    return out


def event_nonce(from_addr: str, to_addr: str, counter: int) -> bytes:
    """First 12 bytes of keccak256(abi.encode(from, to, counter))."""
    encoded = (
        int(from_addr, 16).to_bytes(32, "big") + int(to_addr, 16).to_bytes(32, "big") + counter.to_bytes(32, "big")
    )
    return keccak256(encoded)[:12]


# ============ AES-256-GCM ============

_AES_SBOX = None


def _aes_init():
    global _AES_SBOX
    if _AES_SBOX is not None:
        return
    sbox = [0] * 256
    p = q = 1
    while True:
        p = p ^ ((p << 1) & 0xFF) ^ (0x1B if p & 0x80 else 0)
        q ^= q << 1
        q ^= q << 2
        q ^= q << 4
        q &= 0xFF
        q ^= 0x09 if q & 0x80 else 0
        sbox[p] = (q ^ _rol8(q, 1) ^ _rol8(q, 2) ^ _rol8(q, 3) ^ _rol8(q, 4)) ^ 0x63
        if p == 1:
            break
    sbox[0] = 0x63
    _AES_SBOX = sbox


def _rol8(v, s):
    return ((v << s) | (v >> (8 - s))) & 0xFF


def _xtime(a):
    return ((a << 1) ^ 0x1B) & 0xFF if a & 0x80 else a << 1


def _aes256_expand_key(key):
    _aes_init()
    words = [list(key[4 * i : 4 * i + 4]) for i in range(8)]
    rcon = 1
    for i in range(8, 60):
        t = list(words[i - 1])
        if i % 8 == 0:
            t = [_AES_SBOX[b] for b in t[1:] + t[:1]]
            t[0] ^= rcon
            rcon = _xtime(rcon)
        elif i % 8 == 4:
            t = [_AES_SBOX[b] for b in t]
        words.append([words[i - 8][j] ^ t[j] for j in range(4)])
    return [bytes(sum((words[4 * r + c] for c in range(4)), [])) for r in range(15)]


def _aes256_encrypt_block(round_keys, block):
    state = [block[i] ^ round_keys[0][i] for i in range(16)]
    for rnd in range(1, 15):
        state = [_AES_SBOX[b] for b in state]
        state = [state[(i + 4 * (i % 4)) % 16] for i in range(16)]  # shift rows (column-major layout)
        if rnd < 14:
            mixed = []
            for c in range(4):
                col = state[4 * c : 4 * c + 4]
                mixed += [
                    _xtime(col[0]) ^ _xtime(col[1]) ^ col[1] ^ col[2] ^ col[3],
                    col[0] ^ _xtime(col[1]) ^ _xtime(col[2]) ^ col[2] ^ col[3],
                    col[0] ^ col[1] ^ _xtime(col[2]) ^ _xtime(col[3]) ^ col[3],
                    _xtime(col[0]) ^ col[0] ^ col[1] ^ col[2] ^ _xtime(col[3]),
                ]
            state = mixed
        state = [state[i] ^ round_keys[rnd][i] for i in range(16)]
    return bytes(state)


def _ghash(h_int, data):
    y = 0
    for i in range(0, len(data), 16):
        y ^= int.from_bytes(data[i : i + 16], "big")
        z, v = 0, y
        for bit in range(128):
            if (h_int >> (127 - bit)) & 1:
                z ^= v
            v = (v >> 1) ^ (0xE1 << 120) if v & 1 else v >> 1
        y = z
    return y


def aes256_gcm_decrypt(key: bytes, nonce: bytes, payload: bytes) -> bytes:
    """Decrypt ciphertext||tag; raises ValueError on tag mismatch. Pure-Python fallback path."""
    try:
        from cryptography.hazmat.primitives.ciphers.aead import AESGCM  # type: ignore

        return AESGCM(key).decrypt(nonce, payload, None)
    except ImportError:
        pass

    if len(payload) < 16:
        raise ValueError("payload shorter than a GCM tag")
    ciphertext, tag = payload[:-16], payload[-16:]

    round_keys = _aes256_expand_key(key)
    h_int = int.from_bytes(_aes256_encrypt_block(round_keys, b"\x00" * 16), "big")
    j0 = nonce + b"\x00\x00\x00\x01"

    padded = ciphertext + b"\x00" * (-len(ciphertext) % 16)
    lengths = (0).to_bytes(8, "big") + (8 * len(ciphertext)).to_bytes(8, "big")
    s = _ghash(h_int, padded + lengths)
    expected_tag = (s ^ int.from_bytes(_aes256_encrypt_block(round_keys, j0), "big")).to_bytes(16, "big")
    if not hmac.compare_digest(expected_tag, tag):
        raise ValueError("GCM tag mismatch (wrong key, nonce, or corrupted ciphertext)")

    plaintext = b""
    counter = int.from_bytes(j0, "big")
    for i in range(0, len(ciphertext), 16):
        counter += 1
        keystream = _aes256_encrypt_block(round_keys, counter.to_bytes(16, "big"))
        block = ciphertext[i : i + 16]
        plaintext += bytes(a ^ b for a, b in zip(block, keystream))
    return plaintext


# ============ decryption entry points ============


def decrypt(privkey, peer_pubkey, from_addr, to_addr, counter, payload) -> int:
    key = derive_aes_key(privkey, peer_pubkey)
    plaintext = aes256_gcm_decrypt(key, event_nonce(from_addr, to_addr, counter), payload)
    if len(plaintext) != 32:
        raise ValueError(f"expected abi.encode(uint256) plaintext, got {len(plaintext)} bytes")
    return int.from_bytes(plaintext, "big")


def scan_decrypt(privkey, peer_pubkey, from_addr, to_addr, max_counter, payload):
    for counter in range(1, max_counter + 1):
        try:
            return counter, decrypt(privkey, peer_pubkey, from_addr, to_addr, counter, payload)
        except ValueError:
            continue
    raise ValueError(f"no counter in 1..{max_counter} produced a valid GCM tag")


# ============ self-test (vectors pinned from the Seismic precompiles) ============


def self_test():
    # 0x65 with privkey=1, peer=G (test/integration/seismic/MYieldToOneSeismic.t.sol)
    out = hkdf_sha256(ecdh_shared_secret((1).to_bytes(32, "big"), bytes.fromhex(
        "0279be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798")), b"aes-gcm key")
    assert out.hex() == "a59676edf7d8f47a0cc8ac42e29566d4a1763eeeba8794d6a196029a1477f147", "ECDH(0x65) vector"

    # 0x68 with ikm = uint256(0xdeadbeef)
    out = hkdf_sha256((0xDEADBEEF).to_bytes(32, "big"), b"seismic_hkdf_105")
    assert out.hex() == "eb3cb17dcdc55d1119c98cac1e12bb13a95f81b50a0784750bdcf92787c4985e", "HKDF(0x68) vector"

    # 0x66/0x67 with key=uint256(0x42), nonce=uint96(7), plaintext=abi.encode(123456)
    payload = bytes.fromhex(
        "bae51be0c992f7c0c34d03a9431aebdc7732c399729054925a094d8f373d65c18c9eec49034da029df615639016e16c8")
    plaintext = aes256_gcm_decrypt((0x42).to_bytes(32, "big"), (7).to_bytes(12, "big"), payload)
    assert plaintext == (123456).to_bytes(32, "big"), "AES-GCM(0x66) vector"

    # keccak256 sanity (empty-input digest)
    assert keccak256(b"").hex() == "c5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470", "keccak256"

    # Full pipeline vector emitted by test_shieldedTransfer_realKeys_recipientDecrypts (sforge, real precompiles)
    amount = decrypt(
        bytes.fromhex("af22e8d07271a11eb94550f14173e09ce37902708dfc142a4bc1884ffcb7e688"),
        bytes.fromhex("03a0a51f0cf98915ae76cfcf9d3993a0e35bbbed7a457dbcf66ed6500126e2be1f"),
        "0x328809Bc894f92807417D2dAD6b7C998c1aFdac6",
        "0x61469988af724818Ab0078FC6BFd2c8ddCf174A9",
        1,
        bytes.fromhex("9acb56d05afbec4d447e084de68773a265f475247ccd7e4f1a2371e3711ca7fca582491634286d9be37f457c0b6d6877"),
    )
    assert amount == 1_000_000_000, f"full pipeline vector: got {amount}"

    # --scan finds the same counter
    counter, amount = scan_decrypt(
        bytes.fromhex("af22e8d07271a11eb94550f14173e09ce37902708dfc142a4bc1884ffcb7e688"),
        bytes.fromhex("03a0a51f0cf98915ae76cfcf9d3993a0e35bbbed7a457dbcf66ed6500126e2be1f"),
        "0x328809Bc894f92807417D2dAD6b7C998c1aFdac6",
        "0x61469988af724818Ab0078FC6BFd2c8ddCf174A9",
        16,
        bytes.fromhex("9acb56d05afbec4d447e084de68773a265f475247ccd7e4f1a2371e3711ca7fca582491634286d9be37f457c0b6d6877"),
    )
    assert (counter, amount) == (1, 1_000_000_000), "scan vector"

    print("self-test: all vectors pass")


# ============ CLI ============


def _hex_bytes(value):
    return bytes.fromhex(value[2:] if value.startswith("0x") else value)


def main():
    if len(sys.argv) == 1:
        print(__doc__)
        sys.exit(2)

    parser = argparse.ArgumentParser(add_help=True, description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--privkey", type=_hex_bytes)
    parser.add_argument("--peer-pubkey", type=_hex_bytes)
    parser.add_argument("--from", dest="from_addr")
    parser.add_argument("--to", dest="to_addr")
    parser.add_argument("--nonce-counter", type=int)
    parser.add_argument("--scan", type=int, metavar="MAX_N")
    parser.add_argument("--ciphertext", type=_hex_bytes)
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()

    if args.self_test:
        self_test()
        return

    required = [args.privkey, args.peer_pubkey, args.from_addr, args.to_addr, args.ciphertext]
    if any(v is None for v in required) or (args.nonce_counter is None and args.scan is None):
        parser.error("need --privkey, --peer-pubkey, --from, --to, --ciphertext and one of --nonce-counter/--scan")

    if args.nonce_counter is not None:
        counter = args.nonce_counter
        amount = decrypt(args.privkey, args.peer_pubkey, args.from_addr, args.to_addr, counter, args.ciphertext)
    else:
        counter, amount = scan_decrypt(
            args.privkey, args.peer_pubkey, args.from_addr, args.to_addr, args.scan, args.ciphertext
        )

    print(f"nonce-counter: {counter}")
    print(f"amount: {amount}")


if __name__ == "__main__":
    main()

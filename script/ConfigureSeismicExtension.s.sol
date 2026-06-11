// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.26;

import { console } from "../lib/forge-std/src/console.sol";

import { ScriptBase } from "./ScriptBase.s.sol";

import { IMYieldToOne } from "../src/projects/yieldToOne/interfaces/IMYieldToOne.sol";
import { ISwapFacility } from "../src/swap/interfaces/ISwapFacility.sol";

/**
 * @title  ConfigureSeismicExtension
 * @notice Post-deploy configuration for a Seismic extension: approves the extension on the
 *         SwapFacility and allowlists the infra contracts (Portal, LimitOrderProtocol).
 * @dev    Plain txs only — the contract encryption key is installed separately via
 *         script/set-contract-key.sh (see its header for why that step cannot live here).
 */
contract ConfigureSeismicExtension is ScriptBase {
    function run() public {
        address deployer = vm.addr(vm.envUint("PRIVATE_KEY"));
        address extension = vm.envAddress("EXTENSION_PROXY");
        address swapFacility = _getSwapFacility();

        // LIMIT_ORDER_PROTOCOL is optional: not yet deployed on Seismic testnet (see AUDIT-SCOPE.md).
        address limitOrderProtocol = vm.envOr("LIMIT_ORDER_PROTOCOL", address(0));

        address[] memory infra = new address[](limitOrderProtocol == address(0) ? 1 : 2);
        infra[0] = vm.envAddress("PORTAL");
        if (limitOrderProtocol != address(0)) infra[1] = limitOrderProtocol;

        vm.startBroadcast(deployer);

        ISwapFacility(swapFacility).setAdminApprovedExtension(extension, true);
        IMYieldToOne(extension).setAllowlisted(infra, true);

        vm.stopBroadcast();

        console.log("Extension approved on SwapFacility:", extension);
        console.log("Allowlisted Portal:", infra[0]);
        if (limitOrderProtocol != address(0)) console.log("Allowlisted LimitOrderProtocol:", limitOrderProtocol);
    }
}

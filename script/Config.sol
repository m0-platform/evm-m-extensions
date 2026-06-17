// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

contract Config {
    error UnsupportedChain(uint256 chainId);

    struct DeployConfig {
        address mToken;
        address wrappedMToken;
        address registrar;
        address uniswapV3Router;
        address admin;
    }

    struct MEarnerManagerConfig {
        string contractName; // used for computing Salt
        string extensionName; // ERC20 name
        string symbol;
        address admin;
        address earnerManager;
        address feeRecipient;
        address pauser;
    }

    struct YieldToOneConfig {
        string contractName; // used for computing Salt
        string extensionName; // ERC20 name
        string symbol;
        address yieldRecipient;
        address admin;
        address freezeManager;
        address yieldRecipientManager;
        address pauser;
        address allowlistAdmin;
    }

    struct YieldToOneForcedTransferConfig {
        string contractName; // used for computing Salt
        string extensionName; // ERC20 name
        string symbol;
        address yieldRecipient;
        address admin;
        address freezeManager;
        address yieldRecipientManager;
        address pauser;
        address forcedTransferManager;
        address allowlistAdmin;
    }

    struct JMIExtensionConfig {
        string contractName; // used for computing Salt
        string extensionName; // ERC20 name
        string symbol;
        address yieldRecipient;
        address admin;
        address assetCapManager;
        address freezeManager;
        address pauser;
        address yieldRecipientManager;
        address allowlistAdmin;
    }

    struct YieldToAllWithFeeConfig {
        string contractName; // used for computing Salt
        string extensionName; // ERC20 name
        string symbol;
        uint16 feeRate;
        address feeRecipient;
        address admin;
        address feeManager;
        address claimRecipientManager;
        address freezeManager;
        address pauser;
    }

    // Mainnet chain IDs
    uint256 public constant ETHEREUM_CHAIN_ID = 1;
    uint256 public constant ARBITRUM_CHAIN_ID = 42161;
    uint256 public constant OPTIMISM_CHAIN_ID = 10;
    uint256 public constant HYPER_EVM_CHAIN_ID = 999;
    uint256 public constant PLUME_CHAIN_ID = 98866;
    uint256 public constant BSC_CHAIN_ID = 56;
    uint256 public constant MANTRA_CHAIN_ID = 5888;
    uint256 public constant BASE_CHAIN_ID = 8453;
    uint256 public constant SONEIUM_CHAIN_ID = 1868;
    uint256 public constant PLASMA_CHAIN_ID = 9745;
    uint256 public constant CITREA_CHAIN_ID = 4114;
    uint256 public constant SEI_CHAIN_ID = 1329;
    uint256 public constant LINEA_CHAIN_ID = 59144;
    uint256 public constant ZG_CHAIN_ID = 16661;

    // Testnet chain IDs
    uint256 public constant LOCAL_CHAIN_ID = 31337;
    uint256 public constant SEPOLIA_CHAIN_ID = 11155111;
    uint256 public constant ARBITRUM_SEPOLIA_CHAIN_ID = 421614;
    uint256 public constant OPTIMISM_SEPOLIA_CHAIN_ID = 11155420;
    uint256 public constant APECHAIN_TESTNET_CHAIN_ID = 33111;
    uint256 public constant BSC_TESTNET_CHAIN_ID = 97;
    uint256 public constant SONEIUM_TESTNET_CHAIN_ID = 1946;
    uint256 public constant BASE_SEPOLIA_CHAIN_ID = 84532;
    uint256 public constant SEISMIC_TESTNET_CHAIN_ID = 5124;

    address public constant DEPLOYER = 0xF2f1ACbe0BA726fEE8d75f3E32900526874740BB;
    address public constant TESTNET_OWNER = 0x12b1A4226ba7D9Ad492779c924b0fC00BDCb6217;

    address public constant M_TOKEN = 0x866A2BF4E572CbcF37D5071A7a58503Bfb36be1b;
    address public constant WRAPPED_M_TOKEN = 0x437cc33344a0B27A429f795ff6B469C72698B291;
    address public constant REGISTRAR = 0x119FbeeDD4F4f4298Fb59B720d5654442b81ae2c;

    // Same address across all supported chains
    address public constant UNISWAP_V3_ROUTER = 0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45;

    address public constant UNISWAP_ROUTER_SEPOLIA = 0x3bFA4769FB09eefC5a80d6E87c3B9C650f7Ae48E;
    address public constant UNISWAP_ROUTER_ARBITRUM_SEPOLIA = 0x101F443B4d1b059569D643917553c771E1b9663E;

    function _getDeployConfig(uint256 chainId_) internal pure returns (DeployConfig memory) {
        DeployConfig memory config;

        // Mainnet configs
        if (chainId_ == ETHEREUM_CHAIN_ID) {
            config = _getDefaultDeployConfig();
            config.uniswapV3Router = UNISWAP_V3_ROUTER;
            return config;
        }

        if (chainId_ == ARBITRUM_CHAIN_ID) {
            config = _getDefaultDeployConfig();
            config.uniswapV3Router = UNISWAP_V3_ROUTER;
            return config;
        }

        if (chainId_ == OPTIMISM_CHAIN_ID) return _getDefaultDeployConfig();
        if (chainId_ == HYPER_EVM_CHAIN_ID) return _getDefaultDeployConfig();
        if (chainId_ == PLUME_CHAIN_ID) return _getDefaultDeployConfig();
        if (chainId_ == BSC_CHAIN_ID) return _getDefaultDeployConfig();
        if (chainId_ == MANTRA_CHAIN_ID) return _getDefaultDeployConfig();
        if (chainId_ == BASE_CHAIN_ID) return _getDefaultDeployConfig();
        if (chainId_ == PLASMA_CHAIN_ID) return _getDefaultDeployConfig();
        if (chainId_ == SONEIUM_CHAIN_ID) {
            config = _getDefaultDeployConfig();
            config.uniswapV3Router = UNISWAP_V3_ROUTER;
            return config;
        }
        if (chainId_ == CITREA_CHAIN_ID) return _getDefaultDeployConfig();
        if (chainId_ == SEI_CHAIN_ID) return _getDefaultDeployConfig();
        if (chainId_ == LINEA_CHAIN_ID) return _getDefaultDeployConfig();
        if (chainId_ == ZG_CHAIN_ID) return _getDefaultDeployConfig();

        // Testnet configs
        if (chainId_ == LOCAL_CHAIN_ID) return _getDefaultDeployConfig();
        if (chainId_ == SEPOLIA_CHAIN_ID) {
            config = _getDefaultDeployConfig();
            config.uniswapV3Router = UNISWAP_ROUTER_SEPOLIA;
            return config;
        }

        if (chainId_ == ARBITRUM_SEPOLIA_CHAIN_ID) {
            config = _getDefaultDeployConfig();
            config.uniswapV3Router = UNISWAP_ROUTER_ARBITRUM_SEPOLIA;
            return config;
        }

        if (chainId_ == OPTIMISM_SEPOLIA_CHAIN_ID) return _getDefaultDeployConfig();
        if (chainId_ == APECHAIN_TESTNET_CHAIN_ID) return _getDefaultDeployConfig();
        if (chainId_ == BSC_TESTNET_CHAIN_ID) return _getDefaultDeployConfig();
        if (chainId_ == BASE_SEPOLIA_CHAIN_ID) return _getDefaultDeployConfig();
        if (chainId_ == SEISMIC_TESTNET_CHAIN_ID) return _getDefaultDeployConfig();
        if (chainId_ == SONEIUM_TESTNET_CHAIN_ID) {
            config = _getDefaultDeployConfig();
            config.registrar = 0x09ddB94dE27d26Fa426276bF33932594B257F9B6;
            config.uniswapV3Router = UNISWAP_V3_ROUTER;
            return config;
        }

        revert UnsupportedChain(chainId_);
    }

    /// @dev Default config for EVM chains
    function _getDefaultDeployConfig() internal pure returns (DeployConfig memory) {
        return
            DeployConfig({
                mToken: M_TOKEN,
                wrappedMToken: WRAPPED_M_TOKEN,
                registrar: REGISTRAR,
                uniswapV3Router: address(0),
                admin: DEPLOYER
            });
    }

    function _getWhitelistedTokens(uint256 chainId_) internal pure returns (address[] memory whitelistedTokens) {
        if (chainId_ == ETHEREUM_CHAIN_ID) {
            whitelistedTokens = new address[](2);
            whitelistedTokens[0] = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48; // USDC
            whitelistedTokens[1] = 0xdAC17F958D2ee523a2206206994597C13D831ec7; // USDT
        }

        if (chainId_ == ARBITRUM_CHAIN_ID) {
            whitelistedTokens = new address[](1);
            whitelistedTokens[0] = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831; // USDC
        }

        if (chainId_ == SONEIUM_CHAIN_ID) {
            whitelistedTokens = new address[](1);
            whitelistedTokens[0] = 0xbA9986D2381edf1DA03B0B9c1f8b00dc4AacC369; // USDC.E (bridged)
        }

        if (chainId_ == SEPOLIA_CHAIN_ID) {
            whitelistedTokens = new address[](2);
            whitelistedTokens[0] = 0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238; // USDC
            whitelistedTokens[1] = 0xaA8E23Fb1079EA71e0a56F48a2aA51851D8433D0; // USDT
        }

        if (chainId_ == ARBITRUM_SEPOLIA_CHAIN_ID) {
            whitelistedTokens = new address[](1);
            whitelistedTokens[0] = 0x75faf114eafb1BDbe2F0316DF893fd58CE46AA4d; // USDC
        }

        return whitelistedTokens;
    }
}

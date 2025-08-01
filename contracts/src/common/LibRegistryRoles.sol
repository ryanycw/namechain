// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

library LibRegistryRoles {
    uint256 internal constant ROLE_REGISTRAR = 1 << 0;
    uint256 internal constant ROLE_REGISTRAR_ADMIN = ROLE_REGISTRAR << 128;

    uint256 internal constant ROLE_RENEW = 1 << 4;
    uint256 internal constant ROLE_RENEW_ADMIN = ROLE_RENEW << 128;

    uint256 internal constant ROLE_SET_SUBREGISTRY = 1 << 8;
    uint256 internal constant ROLE_SET_SUBREGISTRY_ADMIN = ROLE_SET_SUBREGISTRY << 128;

    uint256 internal constant ROLE_SET_RESOLVER = 1 << 12;
    uint256 internal constant ROLE_SET_RESOLVER_ADMIN = ROLE_SET_RESOLVER << 128;

    uint256 internal constant ROLE_SET_TOKEN_OBSERVER = 1 << 16;
    uint256 internal constant ROLE_SET_TOKEN_OBSERVER_ADMIN = ROLE_SET_TOKEN_OBSERVER << 128;

    uint256 internal constant ROLE_BURN = 1 << 20;
    uint256 internal constant ROLE_BURN_ADMIN = ROLE_BURN << 128;
}

// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {IRegistry} from "./IRegistry.sol";

/**
 * @title IStandardRegistry
 * @dev Interface for the a standard registry.
 */
interface IStandardRegistry is IRegistry {
    /**
     * @dev Error emitted when a name is already registered.
     */
    error NameAlreadyRegistered(string label);

    /**
     * @dev Error emitted when a name has expired.
     */
    error NameExpired(uint256 tokenId);

    /**
     * @dev Error emitted when a name cannot be reduced in expiration.
     */
    error CannotReduceExpiration(uint64 oldExpiration, uint64 newExpiration);

    /**
     * @dev Error emitted when a name cannot be set to a past expiration.
     */
    error CannotSetPastExpiration(uint64 expiry);

    /**
     * @dev Event emitted when a name is renewed.
     */
    event NameRenewed(uint256 indexed tokenId, uint64 newExpiration, address renewedBy);

    /**
     * @dev Event emitted when a name is burned.
     */
    event NameBurned(uint256 indexed tokenId, address burnedBy);

    /**
     * @dev Registers a new subdomain.
     * @param label The label to register.
     * @param owner The address of the owner of the subdomain.
     * @param registry The registry to set as the subdomain.
     * @param resolver The resolver to set for the subdomain.
     * @param roleBitmap The role bitmap to set for the subdomain.
     * @param expires The expiration date of the subdomain.
     */
    function register(
        string calldata label,
        address owner,
        IRegistry registry,
        address resolver,
        uint256 roleBitmap,
        uint64 expires
    ) external returns (uint256 tokenId);

    /**
     * @dev Renews a subdomain.
     * @param tokenId The token ID of the subdomain to renew.
     * @param expires The expiration date of the subdomain.
     */
    function renew(uint256 tokenId, uint64 expires) external;

    /**
     * @dev Burns a subdomain.
     * @param tokenId The token ID of the subdomain to burn.
     */
    function burn(uint256 tokenId) external;

    /**
     * @dev Sets a subdomain.
     * @param tokenId The token ID of the subdomain to set.
     * @param registry The registry to set as the subdomain.
     */
    function setSubregistry(uint256 tokenId, IRegistry registry) external;

    /**
     * @dev Sets a resolver for a subdomain.
     * @param tokenId The token ID of the subdomain to set a resolver for.
     * @param resolver The resolver to set for the subdomain.
     */
    function setResolver(uint256 tokenId, address resolver) external;

    /**
     * @dev Fetches the expiry date of a subdomain.
     * @param tokenId The token ID of the subdomain to fetch the expiry for.
     * @return The expiry date of the subdomain.
     */
    function getExpiry(uint256 tokenId) external view returns (uint64);
}

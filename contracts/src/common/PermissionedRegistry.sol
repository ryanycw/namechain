// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {ERC1155Singleton} from "./ERC1155Singleton.sol";
import {IERC1155Singleton} from "./IERC1155Singleton.sol";
import {IRegistry} from "./IRegistry.sol";
import {IRegistryDatastore} from "./IRegistryDatastore.sol";
import {BaseRegistry} from "./BaseRegistry.sol";
import {EnhancedAccessControl} from "./EnhancedAccessControl.sol";
import {MetadataMixin} from "./MetadataMixin.sol";
import {IRegistryMetadata} from "./IRegistryMetadata.sol";
import {SimpleRegistryMetadata} from "./SimpleRegistryMetadata.sol";
import {NameUtils} from "./NameUtils.sol";
import {IPermissionedRegistry} from "./IPermissionedRegistry.sol";
import {ITokenObserver} from "./ITokenObserver.sol";
import {LibRegistryRoles} from "./LibRegistryRoles.sol";

contract PermissionedRegistry is BaseRegistry, EnhancedAccessControl, IPermissionedRegistry, MetadataMixin {
    event TokenRegenerated(uint256 oldTokenId, uint256 newTokenId);

    mapping(uint256 => ITokenObserver) public tokenObservers;

    modifier onlyNonExpiredTokenRoles(uint256 tokenId, uint256 roleBitmap) {
        _checkRoles(getTokenIdResource(tokenId), roleBitmap, _msgSender());
        (, uint64 expires,) = datastore.getSubregistry(tokenId);
        if (expires < block.timestamp) {
            revert NameExpired(tokenId);
        }
        _;
    }

    constructor(IRegistryDatastore _datastore, IRegistryMetadata _metadata, address _ownerAddress, uint256 _ownerRoles)
        BaseRegistry(_datastore)
        MetadataMixin(_metadata)
    {
        _grantRoles(ROOT_RESOURCE, _ownerRoles, _ownerAddress, false);

        if (address(_metadata) == address(0)) {
            _updateMetadataProvider(new SimpleRegistryMetadata());
        }
    }

    function uri(uint256 tokenId) public view override returns (string memory) {
        return tokenURI(tokenId);
    }

    function ownerOf(uint256 tokenId)
        public
        view
        virtual
        override(ERC1155Singleton, IERC1155Singleton)
        returns (address)
    {
        (, uint64 expires,) = datastore.getSubregistry(tokenId);
        if (expires < block.timestamp) {
            return address(0);
        }
        return super.ownerOf(tokenId);
    }

    function register(
        string calldata label,
        address owner,
        IRegistry registry,
        address resolver,
        uint256 roleBitmap,
        uint64 expires
    ) public virtual override onlyRootRoles(LibRegistryRoles.ROLE_REGISTRAR) returns (uint256 tokenId) {
        uint64 oldExpiry;
        uint32 tokenIdVersion;
        (tokenId, oldExpiry, tokenIdVersion) = getNameData(label);

        if (oldExpiry >= block.timestamp) {
            revert NameAlreadyRegistered(label);
        }

        if (expires < block.timestamp) {
            revert CannotSetPastExpiration(expires);
        }

        // if there is a previous owner, burn the token
        address previousOwner = super.ownerOf(tokenId);
        if (previousOwner != address(0)) {
            _burn(previousOwner, tokenId, 1);
            tokenIdVersion++; // so we have a fresh acl
        }
        tokenId = _generateTokenId(tokenId, address(registry), expires, tokenIdVersion);

        _mint(owner, tokenId, 1, "");
        _grantRoles(getTokenIdResource(tokenId), roleBitmap, owner, false);

        datastore.setResolver(tokenId, resolver, 0, 0);

        emit NewSubname(tokenId, label);

        return tokenId;
    }

    function setTokenObserver(uint256 tokenId, ITokenObserver observer)
        public
        override
        onlyNonExpiredTokenRoles(tokenId, LibRegistryRoles.ROLE_SET_TOKEN_OBSERVER)
    {
        tokenObservers[tokenId] = observer;
        emit TokenObserverSet(tokenId, address(observer));
    }

    function renew(uint256 tokenId, uint64 expires)
        public
        override
        onlyNonExpiredTokenRoles(tokenId, LibRegistryRoles.ROLE_RENEW)
    {
        (address subregistry, uint64 oldExpiration, uint32 tokenIdVersion) = datastore.getSubregistry(tokenId);
        if (expires < oldExpiration) {
            revert CannotReduceExpiration(oldExpiration, expires);
        }

        datastore.setSubregistry(tokenId, subregistry, expires, tokenIdVersion);

        ITokenObserver observer = tokenObservers[tokenId];
        if (address(observer) != address(0)) {
            observer.onRenew(tokenId, expires, msg.sender);
        }

        emit NameRenewed(tokenId, expires, msg.sender);
    }

    /**
     * @dev Burn a name.
     *      This will destroy the name and remove it from the registry.
     *
     * @param tokenId The token ID of the name to relinquish.
     */
    function burn(uint256 tokenId) external override onlyNonExpiredTokenRoles(tokenId, LibRegistryRoles.ROLE_BURN) {
        _burn(ownerOf(tokenId), tokenId, 1);

        datastore.setSubregistry(tokenId, address(0), 0, 0);
        datastore.setResolver(tokenId, address(0), 0, 0);

        emit NameBurned(tokenId, msg.sender);
    }

    function getSubregistry(string calldata label)
        external
        view
        virtual
        override(BaseRegistry, IRegistry)
        returns (IRegistry)
    {
        uint256 canonicalId = NameUtils.labelToCanonicalId(label);
        (address subregistry, uint64 expires,) = datastore.getSubregistry(canonicalId);
        if (expires <= block.timestamp) {
            return IRegistry(address(0));
        }
        return IRegistry(subregistry);
    }

    function getResolver(string calldata label)
        external
        view
        virtual
        override(BaseRegistry, IRegistry)
        returns (address)
    {
        uint256 canonicalId = NameUtils.labelToCanonicalId(label);
        (, uint64 expires,) = datastore.getSubregistry(canonicalId);
        if (expires <= block.timestamp) {
            return address(0);
        }
        (address resolver,,) = datastore.getResolver(canonicalId);
        return resolver;
    }

    function setSubregistry(uint256 tokenId, IRegistry registry)
        external
        override
        onlyNonExpiredTokenRoles(tokenId, LibRegistryRoles.ROLE_SET_SUBREGISTRY)
    {
        (, uint64 expires, uint32 tokenIdVersion) = datastore.getSubregistry(tokenId);
        datastore.setSubregistry(tokenId, address(registry), expires, tokenIdVersion);
    }

    function setResolver(uint256 tokenId, address resolver)
        external
        override
        onlyNonExpiredTokenRoles(tokenId, LibRegistryRoles.ROLE_SET_RESOLVER)
    {
        datastore.setResolver(tokenId, resolver, 0, 0);
    }

    function getNameData(string calldata label)
        public
        view
        returns (uint256 tokenId, uint64 expiry, uint32 tokenIdVersion)
    {
        uint256 canonicalId = NameUtils.labelToCanonicalId(label);
        (, expiry, tokenIdVersion) = datastore.getSubregistry(canonicalId);
        tokenId = _constructTokenId(canonicalId, tokenIdVersion);
    }

    function getExpiry(uint256 tokenId) public view override returns (uint64) {
        (, uint64 expires,) = datastore.getSubregistry(tokenId);
        return expires;
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(BaseRegistry, EnhancedAccessControl, IERC165)
        returns (bool)
    {
        return interfaceId == type(IPermissionedRegistry).interfaceId || super.supportsInterface(interfaceId);
    }

    function getTokenIdResource(uint256 tokenId) public pure returns (bytes32) {
        return bytes32(NameUtils.getCanonicalId(tokenId));
    }

    function getResourceTokenId(bytes32 resource) public view returns (uint256) {
        uint256 canonicalId = uint256(resource);
        (,, uint32 tokenIdVersion) = datastore.getSubregistry(canonicalId);
        return _constructTokenId(canonicalId, tokenIdVersion);
    }

    function getRoleAssigneeCount(uint256 tokenId, uint256 roleBitmap)
        external
        view
        override
        returns (uint256 counts, uint256 mask)
    {
        return getAssigneeCount(getTokenIdResource(tokenId), roleBitmap);
    }

    // Internal/private methods

    /**
     * @dev Override the base registry _update function to transfer the roles to the new owner when the token is transferred.
     */
    function _update(address from, address to, uint256[] memory ids, uint256[] memory values)
        internal
        virtual
        override
    {
        super._update(from, to, ids, values);

        for (uint256 i = 0; i < ids.length; ++i) {
            /*
            in _regenerateToken, we burn the token and then mint a new one. This flow below ensures the roles go from owner => zeroAddr => owner during this process.
            */
            _copyRoles(getTokenIdResource(ids[i]), from, to, false);
            _revokeAllRoles(getTokenIdResource(ids[i]), from, false);
        }
    }

    /**
     * @dev Override the base registry _onRolesGranted function to regenerate the token when the roles are granted.
     */
    function _onRolesGranted(
        bytes32 resource,
        address, /*account*/
        uint256, /*oldRoles*/
        uint256, /*newRoles*/
        uint256 /*roleBitmap*/
    ) internal virtual override {
        uint256 tokenId = getResourceTokenId(resource);
        // skip just-burn/expired tokens
        address owner = ownerOf(tokenId);
        if (owner != address(0)) {
            _regenerateToken(tokenId, owner);
        }
    }

    /**
     * @dev Override the base registry _onRolesRevoked function to regenerate the token when the roles are revoked.
     */
    function _onRolesRevoked(
        bytes32 resource,
        address, /*account*/
        uint256, /*oldRoles*/
        uint256, /*newRoles*/
        uint256 /*roleBitmap*/
    ) internal virtual override {
        uint256 tokenId = getResourceTokenId(resource);
        // skip just-burn/expired tokens
        address owner = ownerOf(tokenId);
        if (owner != address(0)) {
            _regenerateToken(tokenId, owner);
        }
    }

    /**
     * @dev Regenerate a token.
     */
    function _regenerateToken(uint256 tokenId, address owner) internal {
        _burn(owner, tokenId, 1);
        (address registry, uint64 expires, uint32 tokenIdVersion) = datastore.getSubregistry(tokenId);
        uint256 newTokenId = _generateTokenId(tokenId, registry, expires, tokenIdVersion + 1);
        _mint(owner, newTokenId, 1, "");

        emit TokenRegenerated(tokenId, newTokenId);
    }

    /**
     * @dev Regenerate a token id.
     * @param tokenId The token id to regenerate.
     * @param registry The registry to set.
     * @param expires The expiry date to set.
     * @param tokenIdVersion The token id version to set.
     * @return newTokenId The new token id.
     */
    function _generateTokenId(uint256 tokenId, address registry, uint64 expires, uint32 tokenIdVersion)
        internal
        virtual
        returns (uint256 newTokenId)
    {
        newTokenId = _constructTokenId(tokenId, tokenIdVersion);
        datastore.setSubregistry(newTokenId, registry, expires, tokenIdVersion);
    }

    /**
     * @dev Construct a token id from a canonical/token id and a token id version.
     * @param id The canonical/token id to construct the token id from.
     * @param tokenIdVersion The token id version to set.
     * @return newTokenId The new token id.
     */
    function _constructTokenId(uint256 id, uint32 tokenIdVersion) internal pure returns (uint256 newTokenId) {
        newTokenId = NameUtils.getCanonicalId(id) | tokenIdVersion;
    }
}

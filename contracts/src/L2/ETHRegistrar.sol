// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {IETHRegistrar} from "./IETHRegistrar.sol";
import {IRegistry} from "../common/IRegistry.sol";
import {IERC1155Singleton} from "../common/IERC1155Singleton.sol";
import {IPermissionedRegistry} from "../common/IPermissionedRegistry.sol";
import {IPriceOracle} from "@ens/contracts/ethregistrar/IPriceOracle.sol";
import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {NameUtils} from "../common/NameUtils.sol";
import {EnhancedAccessControl, LibEACBaseRoles} from "../common/EnhancedAccessControl.sol";
import {LibRegistryRoles} from "../common/LibRegistryRoles.sol";

contract ETHRegistrar is IETHRegistrar, EnhancedAccessControl {
    uint256 private constant REGISTRATION_ROLE_BITMAP = LibRegistryRoles.ROLE_SET_SUBREGISTRY
        | LibRegistryRoles.ROLE_SET_SUBREGISTRY_ADMIN | LibRegistryRoles.ROLE_SET_RESOLVER
        | LibRegistryRoles.ROLE_SET_RESOLVER_ADMIN | LibRegistryRoles.ROLE_SET_TOKEN_OBSERVER
        | LibRegistryRoles.ROLE_SET_TOKEN_OBSERVER_ADMIN;

    uint256 private constant ROLE_SET_PRICE_ORACLE = 1 << 20;
    uint256 private constant ROLE_SET_PRICE_ORACLE_ADMIN = ROLE_SET_PRICE_ORACLE << 128;

    uint256 private constant ROLE_SET_COMMITMENT_AGES = 1 << 24;
    uint256 private constant ROLE_SET_COMMITMENT_AGES_ADMIN = ROLE_SET_COMMITMENT_AGES << 128;

    uint256 public constant MIN_REGISTRATION_DURATION = 28 days;

    error MaxCommitmentAgeTooLow();
    error UnexpiredCommitmentExists(bytes32 commitment);
    error DurationTooShort(uint64 duration, uint256 minDuration);
    error CommitmentTooNew(bytes32 commitment, uint256 validFrom, uint256 blockTimestamp);
    error CommitmentTooOld(bytes32 commitment, uint256 validTo, uint256 blockTimestamp);
    error NameNotAvailable(string name);
    error InsufficientValue(uint256 required, uint256 provided);

    IPermissionedRegistry public immutable registry;
    IPriceOracle public prices;
    uint256 public minCommitmentAge;
    uint256 public maxCommitmentAge;

    mapping(bytes32 => uint256) public commitments;

    constructor(address _registry, IPriceOracle _prices, uint256 _minCommitmentAge, uint256 _maxCommitmentAge) {
        _grantRoles(ROOT_RESOURCE, LibEACBaseRoles.ALL_ROLES, _msgSender(), true);

        registry = IPermissionedRegistry(_registry);

        if (_maxCommitmentAge <= _minCommitmentAge) {
            revert MaxCommitmentAgeTooLow();
        }

        prices = _prices;
        minCommitmentAge = _minCommitmentAge;
        maxCommitmentAge = _maxCommitmentAge;
    }

    /**
     * @dev Check if a name is valid.
     * @param name The name to check.
     * @return True if the name is valid, false otherwise.
     */
    function valid(string memory name) public pure returns (bool) {
        return bytes(name).length >= 3;
    }

    /**
     * @dev Check if a name is available.
     * @param name The name to check.
     * @return True if the name is available, false otherwise.
     */
    function available(string calldata name) external view returns (bool) {
        (, uint64 expiry,) = registry.getNameData(name);
        return expiry < block.timestamp;
    }

    /**
     * @dev Get the price to register or renew a name.
     * @param name The name to get the price for.
     * @param duration The duration of the registration or renewal.
     * @return price The price to register or renew the name.
     */
    function rentPrice(string memory name, uint256 duration)
        public
        view
        override
        returns (IPriceOracle.Price memory price)
    {
        (, uint64 expiry,) = registry.getNameData(name);
        price = prices.price(name, uint256(expiry), duration);
    }

    /**
     * @dev Make a commitment for a name.
     * @param name The name to commit.
     * @param owner The address of the owner of the name.
     * @param secret The secret of the name.
     * @param subregistry The registry to use for the commitment.
     * @param resolver The resolver to use for the commitment.
     * @param duration The duration of the commitment.
     * @return The commitment.
     */
    function makeCommitment(
        string memory name,
        address owner,
        bytes32 secret,
        address subregistry,
        address resolver,
        uint64 duration
    ) public pure override returns (bytes32) {
        return keccak256(abi.encode(name, owner, secret, subregistry, resolver, duration));
    }

    /**
     * @dev Commit a commitment.
     * @param commitment The commitment to commit.
     */
    function commit(bytes32 commitment) public override {
        if (commitments[commitment] + maxCommitmentAge >= block.timestamp) {
            revert UnexpiredCommitmentExists(commitment);
        }
        commitments[commitment] = block.timestamp;

        emit CommitmentMade(commitment);
    }

    /**
     * @dev Register a name.
     * @param name The name to register.
     * @param owner The owner of the name.
     * @param secret The secret of the name.
     * @param subregistry The subregistry to register the name in.
     * @param resolver The resolver to use for the registration.
     * @param duration The duration of the registration.
     * @return tokenId The token ID of the registered name.
     */
    function register(
        string calldata name,
        address owner,
        bytes32 secret,
        IRegistry subregistry,
        address resolver,
        uint64 duration
    ) external payable returns (uint256 tokenId) {
        uint256 totalPrice = checkPrice(name, duration);

        _consumeCommitment(
            name, duration, makeCommitment(name, owner, secret, address(subregistry), resolver, duration)
        );

        uint64 expiry = uint64(block.timestamp) + duration;
        tokenId = registry.register(name, owner, subregistry, resolver, REGISTRATION_ROLE_BITMAP, expiry);

        if (msg.value > totalPrice) {
            payable(msg.sender).transfer(msg.value - totalPrice);
        }

        emit NameRegistered(name, owner, subregistry, resolver, duration, tokenId);
    }

    /**
     * @dev Renew a name.
     * @param name The name to renew.
     * @param duration The duration of the renewal.
     */
    function renew(string calldata name, uint64 duration) external payable {
        uint256 totalPrice = checkPrice(name, duration);

        (uint256 tokenId, uint64 expiry,) = registry.getNameData(name);

        registry.renew(tokenId, expiry + duration);

        if (msg.value > totalPrice) {
            payable(msg.sender).transfer(msg.value - totalPrice);
        }

        uint64 newExpiry = registry.getExpiry(tokenId);

        emit NameRenewed(name, duration, tokenId, newExpiry);
    }

    function supportsInterface(bytes4 interfaceID) public view override(EnhancedAccessControl) returns (bool) {
        return interfaceID == type(IETHRegistrar).interfaceId || super.supportsInterface(interfaceID);
    }

    function setPriceOracle(IPriceOracle _prices) external onlyRoles(ROOT_RESOURCE, ROLE_SET_PRICE_ORACLE) {
        prices = _prices;
    }

    function setCommitmentAges(uint256 _minCommitmentAge, uint256 _maxCommitmentAge)
        external
        onlyRoles(ROOT_RESOURCE, ROLE_SET_COMMITMENT_AGES)
    {
        if (_maxCommitmentAge <= _minCommitmentAge) {
            revert MaxCommitmentAgeTooLow();
        }
        minCommitmentAge = _minCommitmentAge;
        maxCommitmentAge = _maxCommitmentAge;
    }

    /* Internal functions */

    function _consumeCommitment(string memory name, uint64 duration, bytes32 commitment) internal {
        // Require an old enough commitment.
        uint256 thisCommitmentValidFrom = commitments[commitment] + minCommitmentAge;
        if (thisCommitmentValidFrom > block.timestamp) {
            revert CommitmentTooNew(commitment, thisCommitmentValidFrom, block.timestamp);
        }

        // Commit must not be too old
        uint256 thisCommitmentValidTo = commitments[commitment] + maxCommitmentAge;
        if (thisCommitmentValidTo <= block.timestamp) {
            revert CommitmentTooOld(commitment, thisCommitmentValidTo, block.timestamp);
        }

        // Name must be available
        if (!this.available(name)) {
            revert NameNotAvailable(name);
        }

        if (duration < MIN_REGISTRATION_DURATION) {
            revert DurationTooShort(duration, MIN_REGISTRATION_DURATION);
        }

        delete (commitments[commitment]);
    }

    /**
     * @dev Check the price of a name and revert if insufficient value is provided.
     * @param name The name to check the price for.
     * @param duration The duration of the registration.
     * @return totalPrice The total price of the registration.
     */
    function checkPrice(string memory name, uint64 duration) private view returns (uint256 totalPrice) {
        IPriceOracle.Price memory price = rentPrice(name, duration);
        totalPrice = price.base + price.premium;
        if (msg.value < totalPrice) {
            revert InsufficientValue(totalPrice, msg.value);
        }
    }
}

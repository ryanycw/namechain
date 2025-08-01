// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {ERC165Checker} from "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import {IDedicatedResolverSetters, NODE_ANY} from "./IDedicatedResolverSetters.sol";
import {IExtendedResolver} from "@ens/contracts/resolvers/profiles/IExtendedResolver.sol";
import {IMulticallable} from "@ens/contracts/resolvers/IMulticallable.sol";
import {ENSIP19, COIN_TYPE_ETH, COIN_TYPE_DEFAULT} from "@ens/contracts/utils/ENSIP19.sol";

// resolver features
import {IFeatureSupporter} from "./IFeatureSupporter.sol";
import {ResolverFeatures} from "./ResolverFeatures.sol";

// resolver profiles
import {IAddrResolver} from "@ens/contracts/resolvers/profiles/IAddrResolver.sol";
import {IAddressResolver} from "@ens/contracts/resolvers/profiles/IAddressResolver.sol";
import {IHasAddressResolver} from "@ens/contracts/resolvers/profiles/IHasAddressResolver.sol";
import {ITextResolver} from "@ens/contracts/resolvers/profiles/ITextResolver.sol";
import {IContentHashResolver} from "@ens/contracts/resolvers/profiles/IContentHashResolver.sol";
import {IPubkeyResolver} from "@ens/contracts/resolvers/profiles/IPubkeyResolver.sol";
import {INameResolver} from "@ens/contracts/resolvers/profiles/INameResolver.sol";
import {IABIResolver} from "@ens/contracts/resolvers/profiles/IABIResolver.sol";
import {IInterfaceResolver} from "@ens/contracts/resolvers/profiles/IInterfaceResolver.sol";

/// @title DedicatedResolver
/// @notice An owned resolver that provides the same results for any name.
contract DedicatedResolver is
    ERC165,
    OwnableUpgradeable,
    IDedicatedResolverSetters,
    IFeatureSupporter,
    IExtendedResolver,
    IMulticallable,
    IAddrResolver,
    IAddressResolver,
    IHasAddressResolver,
    ITextResolver,
    IContentHashResolver,
    IPubkeyResolver,
    INameResolver,
    IABIResolver,
    IInterfaceResolver
{
    // profile storage
    mapping(uint256 => bytes) _addresses;
    mapping(string => string) _texts;
    bytes _contenthash;
    bytes32 _pubkeyX;
    bytes32 _pubkeyY;
    mapping(uint256 => bytes) _abis;
    mapping(bytes4 => address) _interfaces;
    string _primary;

    /// @notice The resolver profile cannot be answered.
    /// @dev Error selector: `0x5fe9a5df`
    error UnsupportedResolverProfile(bytes4 selector);

    /// @notice The coin type is not a power of 2.
    /// @dev Error selector: `0xe7cf0ac4`
    error InvalidContentType(uint256 contentType);

    /// @dev Initialize the contract.
    /// @param owner The owner of the resolver.
    function initialize(address owner) public initializer {
        __Ownable_init(owner);
    }

    /// @inheritdoc ERC165
    function supportsInterface(bytes4 interfaceId) public view override(ERC165) returns (bool) {
        return type(IExtendedResolver).interfaceId == interfaceId
            || type(IDedicatedResolverSetters).interfaceId == interfaceId || type(IMulticallable).interfaceId == interfaceId
            || type(IAddrResolver).interfaceId == interfaceId || type(IAddressResolver).interfaceId == interfaceId
            || type(IHasAddressResolver).interfaceId == interfaceId || type(ITextResolver).interfaceId == interfaceId
            || type(IContentHashResolver).interfaceId == interfaceId || type(IPubkeyResolver).interfaceId == interfaceId
            || type(INameResolver).interfaceId == interfaceId || type(IABIResolver).interfaceId == interfaceId
            || type(IInterfaceResolver).interfaceId == interfaceId || type(IFeatureSupporter).interfaceId == interfaceId
            || super.supportsInterface(interfaceId);
    }

    /// @inheritdoc IFeatureSupporter
    function supportsFeature(bytes4 feature) public pure returns (bool) {
        return ResolverFeatures.RESOLVE_MULTICALL == feature || ResolverFeatures.SINGULAR == feature;
    }

    /// @inheritdoc IDedicatedResolverSetters
    function setAddr(uint256 coinType, bytes calldata addressBytes) external onlyOwner {
        if (addressBytes.length != 0 && addressBytes.length != 20 && ENSIP19.isEVMCoinType(coinType)) {
            revert InvalidEVMAddress(addressBytes);
        }
        _addresses[coinType] = addressBytes;
        emit AddressChanged(NODE_ANY, coinType, addressBytes);
        if (coinType == COIN_TYPE_ETH) {
            emit AddrChanged(NODE_ANY, address(bytes20(addressBytes)));
        }
    }

    /// @notice Get the address for coin type.
    ///         If coin type is EVM and empty, defaults to `addr(COIN_TYPE_DEFAULT)`.
    /// @param coinType The coin type.
    /// @return addressBytes The address for the coin type.
    function addr(bytes32, uint256 coinType) public view returns (bytes memory addressBytes) {
        addressBytes = _addresses[coinType];
        if (addressBytes.length == 0 && ENSIP19.chainFromCoinType(coinType) > 0) {
            addressBytes = _addresses[COIN_TYPE_DEFAULT];
        }
    }

    /// @notice Get `addr(60)` as `address`.
    /// @return The address for coin type 60.
    function addr(bytes32) public view returns (address payable) {
        return payable(address(bytes20(addr(NODE_ANY, COIN_TYPE_ETH))));
    }

    /// @inheritdoc IHasAddressResolver
    function hasAddr(bytes32, uint256 coinType) external view returns (bool) {
        return _addresses[coinType].length > 0;
    }

    /// @inheritdoc IDedicatedResolverSetters
    function setText(string calldata key, string calldata value) external onlyOwner {
        _texts[key] = value;
        emit TextChanged(NODE_ANY, key, key, value);
    }

    /// @notice Get the text value for key.
    /// @param key The key.
    /// @return The text value.
    function text(bytes32, string calldata key) external view returns (string memory) {
        return _texts[key];
    }

    /// @inheritdoc IDedicatedResolverSetters
    function setContenthash(bytes calldata hash) external onlyOwner {
        _contenthash = hash;
        emit ContenthashChanged(NODE_ANY, hash);
    }

    /// @notice Get the content hash.
    /// @return The contenthash.
    function contenthash(bytes32) external view returns (bytes memory) {
        return _contenthash;
    }

    /// @inheritdoc IDedicatedResolverSetters
    function setPubkey(bytes32 x, bytes32 y) external onlyOwner {
        _pubkeyX = x;
        _pubkeyY = y;
        emit PubkeyChanged(NODE_ANY, x, y);
    }

    /// @dev Get the public key.
    /// @return x The x coordinate of the public key.
    /// @return y The y coordinate of the public key.
    function pubkey(bytes32) external view returns (bytes32 x, bytes32 y) {
        x = _pubkeyX;
        y = _pubkeyY;
    }

    /// @inheritdoc IDedicatedResolverSetters
    function setABI(uint256 contentType, bytes calldata data) external onlyOwner {
        if (!_isPowerOf2(contentType)) {
            revert InvalidContentType(contentType);
        }
        _abis[contentType] = data;
        emit ABIChanged(NODE_ANY, contentType);
    }

    /// @dev Returns true if `x` has a single bit set.
    function _isPowerOf2(uint256 x) internal pure returns (bool) {
        return x > 0 && (x - 1) & x == 0;
    }

    /// @dev Get the first ABI for the specified content types.
    /// @param contentTypes Union of desired contents types.
    /// @return contentType The first matching content type (or 0 if no match).
    /// @return data The ABI data.
    function ABI(bytes32, uint256 contentTypes) external view returns (uint256 contentType, bytes memory data) {
        for (contentType = 1; contentType > 0 && contentType <= contentTypes; contentType <<= 1) {
            if ((contentType & contentTypes) != 0) {
                data = _abis[contentType];
                if (data.length > 0) {
                    return (contentType, data);
                }
            }
        }
        return (0, "");
    }

    /// @inheritdoc IDedicatedResolverSetters
    function setInterface(bytes4 interfaceId, address implementer) external onlyOwner {
        _interfaces[interfaceId] = implementer;
        emit InterfaceChanged(NODE_ANY, interfaceId, implementer);
    }

    /// @dev Gets the implementer for an interface.
    /// @param interfaceId The interface ID.
    /// @return implementer The implementer address.
    function interfaceImplementer(bytes32, bytes4 interfaceId) external view returns (address implementer) {
        implementer = _interfaces[interfaceId];
        if (implementer == address(0) && ERC165Checker.supportsInterface(addr(NODE_ANY), interfaceId)) {
            implementer = address(this);
        }
    }

    /// @inheritdoc IDedicatedResolverSetters
    function setName(string calldata _name) external onlyOwner {
        _primary = _name;
        emit NameChanged(NODE_ANY, _name);
    }

    /// @dev Get the primary name.
    /// @return The primary name.
    function name(bytes32) external view returns (string memory) {
        return _primary;
    }

    /// @notice Resolve records independent of name.
    /// @dev Revert `UnsupportedResolverProfile` if the record is not supported.
    /// @param data The resolution data, as specified in ENSIP-10..
    /// @return The result of the resolution.
    function resolve(bytes calldata, bytes calldata data) external view returns (bytes memory) {
        (bool ok, bytes memory v) = address(this).staticcall(data);
        if (!ok) {
            assembly {
                revert(add(v, 32), mload(v))
            }
        } else if (v.length == 0) {
            revert UnsupportedResolverProfile(bytes4(data));
        }
        return v;
    }

    /// @notice Perform multiple read or write operations.
    /// @dev Reverts if any call fails.
    function multicall(bytes[] calldata calls) public returns (bytes[] memory results) {
        results = new bytes[](calls.length);
        for (uint256 i; i < calls.length; i++) {
            (bool ok, bytes memory v) = address(this).delegatecall(calls[i]);
            require(ok);
            results[i] = v;
        }
        return results;
    }

    /// @notice Same as `multicall()`.
    /// @dev The purpose of node check is to prevent a trusted operator from modifying
    ///      multiple names.  Since the sole operator of this resolver is the owner and
    ///      it only stores records for a single name, the node check logic can be elided.
    ///
    ///      Additionally, the setters of this resolver do not have `node` as an argument.
    function multicallWithNodeCheck(bytes32, bytes[] calldata calls) external returns (bytes[] memory) {
        return multicall(calls);
    }
}

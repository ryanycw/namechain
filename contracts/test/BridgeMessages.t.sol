// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import {MockL1Bridge} from "../src/mocks/MockL1Bridge.sol";
import {MockL2Bridge} from "../src/mocks/MockL2Bridge.sol";
import {MockBridgeBase} from "../src/mocks/MockBridgeBase.sol";
import {L1EjectionController} from "../src/L1/L1EjectionController.sol";
import {L2BridgeController} from "../src/L2/L2BridgeController.sol";
import {BridgeEncoder} from "../src/common/BridgeEncoder.sol";
import {IBridge, BridgeMessageType, LibBridgeRoles} from "../src/common/IBridge.sol";
import {TransferData} from "../src/common/TransferData.sol";
import {PermissionedRegistry} from "../src/common/PermissionedRegistry.sol";
import {RegistryDatastore} from "../src/common/RegistryDatastore.sol";
import {IRegistryMetadata} from "../src/common/IRegistryMetadata.sol";
import {LibEACBaseRoles} from "../src/common/EnhancedAccessControl.sol";
import {NameUtils} from "../src/common/NameUtils.sol";

contract MockRegistryMetadata is IRegistryMetadata {
    function tokenUri(uint256) external pure override returns (string memory) {
        return "";
    }
}

contract TestBridgeMessages is Test {
    MockL1Bridge l1Bridge;
    MockL2Bridge l2Bridge;
    L1EjectionController l1Controller;
    L2BridgeController l2Controller;
    PermissionedRegistry registry;
    RegistryDatastore datastore;
    MockRegistryMetadata registryMetadata;

    string testLabel = "test";
    address testOwner = address(0x1234);
    address testResolver = address(0x5678);
    uint64 testExpiry = uint64(block.timestamp + 86400);
    uint256 testRoleBitmap = LibEACBaseRoles.ALL_ROLES;

    function setUp() public {
        // Deploy dependencies
        datastore = new RegistryDatastore();
        registryMetadata = new MockRegistryMetadata();

        // Deploy registry
        registry = new PermissionedRegistry(datastore, registryMetadata, address(this), LibEACBaseRoles.ALL_ROLES);

        // Deploy bridges
        l1Bridge = new MockL1Bridge();
        l2Bridge = new MockL2Bridge();

        // Deploy controllers
        l1Controller = new L1EjectionController(registry, l1Bridge);
        l2Controller = new L2BridgeController(l2Bridge, registry, datastore);

        // Set up bridge controllers
        l1Bridge.setEjectionController(l1Controller);
        l2Bridge.setBridgeController(l2Controller);

        // Grant necessary roles
        registry.grantRootRoles(LibEACBaseRoles.ALL_ROLES, address(l1Controller));
        registry.grantRootRoles(LibEACBaseRoles.ALL_ROLES, address(l2Controller));

        // Grant bridge roles so the bridges can call the controllers
        l1Controller.grantRootRoles(LibBridgeRoles.ROLE_EJECTOR, address(l1Bridge));
        l2Controller.grantRootRoles(LibBridgeRoles.ROLE_EJECTOR, address(l2Bridge));
    }

    function test_encodeDecodeEjection() public view {
        bytes memory dnsEncodedName = NameUtils.dnsEncodeEthLabel(testLabel);
        TransferData memory transferData = TransferData({
            label: testLabel,
            owner: testOwner,
            subregistry: address(registry),
            resolver: testResolver,
            expires: testExpiry,
            roleBitmap: testRoleBitmap
        });

        // Encode message
        bytes memory encodedMessage = BridgeEncoder.encodeEjection(dnsEncodedName, transferData);

        // Verify message type
        BridgeMessageType messageType = BridgeEncoder.getMessageType(encodedMessage);
        assertEq(uint256(messageType), uint256(BridgeMessageType.EJECTION));

        // Decode message
        (bytes memory decodedDnsName, TransferData memory decodedData) = BridgeEncoder.decodeEjection(encodedMessage);

        // Verify decoded data
        assertEq(keccak256(decodedDnsName), keccak256(dnsEncodedName));
        assertEq(decodedData.label, transferData.label);
        assertEq(decodedData.owner, transferData.owner);
        assertEq(decodedData.subregistry, transferData.subregistry);
        assertEq(decodedData.resolver, transferData.resolver);
        assertEq(decodedData.expires, transferData.expires);
        assertEq(decodedData.roleBitmap, transferData.roleBitmap);
    }

    function test_encodeDecodeRenewal() public view {
        uint256 tokenId = 12345;
        uint64 newExpiry = uint64(block.timestamp + 86400);

        // Encode message
        bytes memory encodedMessage = BridgeEncoder.encodeRenewal(tokenId, newExpiry);

        // Verify message type
        BridgeMessageType messageType = BridgeEncoder.getMessageType(encodedMessage);
        assertEq(uint256(messageType), uint256(BridgeMessageType.RENEWAL));

        // Decode message
        (uint256 decodedTokenId, uint64 decodedExpiry) = BridgeEncoder.decodeRenewal(encodedMessage);

        // Verify decoded data
        assertEq(decodedTokenId, tokenId);
        assertEq(decodedExpiry, newExpiry);
    }

    function test_l1Bridge_handleRenewal() public {
        // First register a name to renew
        uint256 tokenId = registry.register(testLabel, testOwner, registry, testResolver, testRoleBitmap, testExpiry);

        uint64 newExpiry = uint64(block.timestamp + 86400 * 2);

        // Encode renewal message
        bytes memory renewalMessage = BridgeEncoder.encodeRenewal(tokenId, newExpiry);

        vm.recordLogs();

        // Simulate receiving the message through the bridge
        l1Bridge.receiveMessage(renewalMessage);

        // Verify the renewal was processed
        (, uint64 updatedExpiry,) = datastore.getSubregistry(address(registry), tokenId);
        assertEq(updatedExpiry, newExpiry, "Expiry should be updated");

        // Check for RenewalSynchronized event
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bool foundEvent = false;
        bytes32 eventSig = keccak256("RenewalSynchronized(uint256,uint64)");

        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == eventSig) {
                foundEvent = true;
                break;
            }
        }
        assertTrue(foundEvent, "RenewalSynchronized event should be emitted");
    }

    function test_l2Bridge_revertRenewal() public {
        uint256 tokenId = 12345;
        uint64 newExpiry = uint64(block.timestamp + 86400);

        // Encode renewal message
        bytes memory renewalMessage = BridgeEncoder.encodeRenewal(tokenId, newExpiry);

        // L2 bridge should revert on renewal messages
        vm.expectRevert(MockBridgeBase.RenewalNotSupported.selector);
        l2Bridge.receiveMessage(renewalMessage);
    }

    function test_l1Bridge_sendMessage() public {
        bytes memory testMessage = "test message";

        vm.recordLogs();
        l1Bridge.sendMessage(testMessage);

        // Check for NameBridgedToL2 event
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bool foundEvent = false;
        bytes32 eventSig = keccak256("NameBridgedToL2(bytes)");

        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == eventSig) {
                foundEvent = true;
                break;
            }
        }
        assertTrue(foundEvent, "NameBridgedToL2 event should be emitted");
    }

    function test_l2Bridge_sendMessage_ejection() public {
        bytes memory ejectionMessage = BridgeEncoder.encodeEjection(
            "test",
            TransferData({
                label: testLabel,
                owner: testOwner,
                subregistry: address(registry),
                resolver: testResolver,
                expires: testExpiry,
                roleBitmap: testRoleBitmap
            })
        );

        vm.recordLogs();
        l2Bridge.sendMessage(ejectionMessage);

        // Check for NameBridgedToL1 event
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bool foundEvent = false;
        bytes32 eventSig = keccak256("NameBridgedToL1(bytes)");

        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == eventSig) {
                foundEvent = true;
                break;
            }
        }
        assertTrue(foundEvent, "NameBridgedToL1 event should be emitted");
    }
}

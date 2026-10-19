// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {CabalCoin} from "../src/CabalCoin.sol";

/// @dev Test helper only. This is not an implementation of the production launch factory.
contract TokenFactoryHarness {
    function deploy(bytes32 salt) external returns (CabalCoin) {
        return new CabalCoin{salt: salt}();
    }

    function move(CabalCoin token, address to, uint256 amount) external returns (bool) {
        return token.transfer(to, amount);
    }
}

contract CabalCoinLaunchTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 10 ** 18;

    TokenFactoryHarness private factory;
    CabalCoin private token;
    address private distributor;
    address private pool;
    address private recipient;
    address private claimant;
    address private trader;

    function setUp() public {
        distributor = makeAddr("distributor");
        pool = makeAddr("pool manager role");
        recipient = makeAddr("remainder recipient");
        claimant = makeAddr("claimant");
        trader = makeAddr("trader");
        factory = new TokenFactoryHarness();
        token = factory.deploy(keccak256("cabal deployment test"));
    }

    function test_create2MintsEverythingToFactory() public view {
        address predicted = address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            bytes1(0xff),
                            address(factory),
                            keccak256("cabal deployment test"),
                            keccak256(type(CabalCoin).creationCode)
                        )
                    )
                )
            )
        );
        assertEq(address(token), predicted);
        assertEq(token.balanceOf(address(factory)), SUPPLY);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(token)), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_launchAllocationClaimAndPoolTransfersAreExact() public {
        uint256 swarm = SUPPLY / 10;
        uint256 liquidity = SUPPLY * 85 / 100;
        uint256 remainder = SUPPLY - swarm - liquidity;

        assertTrue(factory.move(token, distributor, swarm));
        assertTrue(factory.move(token, pool, liquidity));
        assertTrue(factory.move(token, recipient, remainder));
        assertEq(token.balanceOf(address(factory)), 0);
        assertEq(token.balanceOf(distributor), swarm);
        assertEq(token.balanceOf(pool), liquidity);
        assertEq(token.balanceOf(recipient), remainder);

        vm.prank(distributor);
        assertTrue(token.transfer(claimant, swarm));
        assertEq(token.balanceOf(distributor), 0);
        assertEq(token.balanceOf(claimant), swarm);

        // Exercise both token transfer directions. Pool pricing and settlement are external.
        uint256 bought = 1_000 ether;
        vm.prank(pool);
        assertTrue(token.transfer(trader, bought));
        assertEq(token.balanceOf(trader), bought);
        assertEq(token.balanceOf(pool), liquidity - bought);
        vm.prank(trader);
        assertTrue(token.transfer(pool, bought));
        assertEq(token.balanceOf(trader), 0);
        assertEq(token.balanceOf(pool), liquidity);
        assertEq(token.totalSupply(), SUPPLY);
    }
}

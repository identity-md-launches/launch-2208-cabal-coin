// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {CabalCoin} from "../src/CabalCoin.sol";

/// @dev Calls the token from a contract, as a router or the pool manager would.
contract TokenCaller {
    function pull(CabalCoin token, address from, address to, uint256 amount) external returns (bool) {
        return token.transferFrom(from, to, amount);
    }

    function send(CabalCoin token, address to, uint256 amount) external returns (bool) {
        return token.transfer(to, amount);
    }
}

contract CabalCoinEdgesTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 10 ** 18;

    CabalCoin private token;
    address private alice;
    address private bob;
    address private spender;

    function setUp() public {
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        spender = makeAddr("spender");
        token = new CabalCoin();
    }

    function test_supplyIsExactlyTenToTheTwentySeven() public view {
        assertEq(token.totalSupply(), 1e27);
        assertEq(token.totalSupply() / 10 ** token.decimals(), 1_000_000_000);
    }

    function test_eachDeploymentMintsOnlyToItsOwnDeployer() public {
        CabalCoin second = new CabalCoin();
        assertEq(second.totalSupply(), SUPPLY);
        assertEq(second.balanceOf(address(this)), SUPPLY);
        // A second deployment does not affect the first.
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(this)), SUPPLY);

        vm.prank(alice);
        CabalCoin third = new CabalCoin();
        assertEq(third.balanceOf(alice), SUPPLY);
        assertEq(third.balanceOf(address(this)), 0);
    }

    function test_transferExactlyBalanceSucceedsOneMoreReverts() public {
        token.transfer(alice, 1000);
        vm.prank(alice);
        assertTrue(token.transfer(bob, 1000));
        assertEq(token.balanceOf(alice), 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 0, 1));
        vm.prank(alice);
        token.transfer(bob, 1);
    }

    function test_transferMaxUintReverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, type(uint256).max
            )
        );
        token.transfer(alice, type(uint256).max);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function test_transferSupplyPlusOneReverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, SUPPLY + 1)
        );
        token.transfer(alice, SUPPLY + 1);
    }

    function test_allowanceOfMaxMinusOneIsFiniteAndDecrements() public {
        token.approve(spender, type(uint256).max - 1);
        vm.prank(spender);
        token.transferFrom(address(this), alice, 1);
        assertEq(token.allowance(address(this), spender), type(uint256).max - 2);
    }

    function test_transferFromExactAllowanceSucceedsThenOneMoreReverts() public {
        token.approve(spender, 7);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 7));
        assertEq(token.allowance(address(this), spender), 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(address(this), alice, 1);
    }

    function test_allowanceCheckedBeforeBalance() public {
        // alice has nothing and approves nothing: the allowance error comes first.
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 5));
        vm.prank(spender);
        token.transferFrom(alice, bob, 5);
    }

    function test_selfApprovalStillRequiredForOwnTransferFrom() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(this), 0, 1));
        token.transferFrom(address(this), alice, 1);

        token.approve(address(this), 1);
        assertTrue(token.transferFrom(address(this), alice, 1));
        assertEq(token.allowance(address(this), address(this)), 0);
        assertEq(token.balanceOf(alice), 1);
    }

    function test_contractSpenderPullsExactlyAndCannotExceed() public {
        TokenCaller router = new TokenCaller();
        token.transfer(alice, 100);
        vm.prank(alice);
        token.approve(address(router), 60);

        assertTrue(router.pull(token, alice, bob, 60));
        assertEq(token.balanceOf(alice), 40);
        assertEq(token.balanceOf(bob), 60);
        assertEq(token.balanceOf(address(router)), 0);

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(router), 0, 1));
        router.pull(token, alice, bob, 1);
    }

    function test_contractHolderCanSendAndReceive() public {
        TokenCaller holder = new TokenCaller();
        token.transfer(address(holder), 500);
        assertTrue(holder.send(token, alice, 500));
        assertEq(token.balanceOf(address(holder)), 0);
        assertEq(token.balanceOf(alice), 500);
    }

    function test_approvalsAreIndependentPerPair() public {
        token.approve(alice, 1);
        token.approve(bob, 2);
        vm.prank(alice);
        token.approve(bob, 3);
        assertEq(token.allowance(address(this), alice), 1);
        assertEq(token.allowance(address(this), bob), 2);
        assertEq(token.allowance(alice, bob), 3);
        assertEq(token.allowance(bob, alice), 0);
        assertEq(token.allowance(alice, address(this)), 0);
    }

    function test_frontRunnableApprovalChangeIsStandardErc20() public {
        // Classic ERC-20 race: a spender who sees 100 -> 50 can spend 100 first and then 50.
        // This is inherent to ERC-20 approve and is documented, not asserted as a defect.
        token.approve(spender, 100);
        vm.prank(spender);
        token.transferFrom(address(this), alice, 100);
        token.approve(spender, 50);
        vm.prank(spender);
        token.transferFrom(address(this), alice, 50);
        assertEq(token.balanceOf(alice), 150);
        assertEq(token.allowance(address(this), spender), 0);
    }

    function test_noEtherAccepted() public {
        vm.deal(address(this), 1 ether);
        (bool ok,) = address(token).call{value: 1}("");
        assertFalse(ok);
        (ok,) = address(token).call{value: 1}(abi.encodeWithSignature("transfer(address,uint256)", alice, 1));
        assertFalse(ok);
        assertEq(address(token).balance, 0);
        assertEq(token.balanceOf(alice), 0);
    }

    function test_unknownSelectorAndShortCalldataRevert() public {
        (bool ok,) = address(token).call(hex"deadbeef");
        assertFalse(ok);
        // transfer selector with truncated arguments
        (ok,) = address(token).call(abi.encodePacked(token.transfer.selector, bytes20(alice)));
        assertFalse(ok);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_approveStoresAnyValue(address owner, address who, uint256 amount) public {
        owner = address(uint160(bound(uint160(owner), 1, type(uint160).max)));
        who = address(uint160(bound(uint160(who), 1, type(uint160).max)));
        vm.prank(owner);
        assertTrue(token.approve(who, amount));
        assertEq(token.allowance(owner, who), amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_twoHopTransferConserves(uint256 first, uint256 second) public {
        first = bound(first, 0, SUPPLY);
        second = bound(second, 0, first);
        token.transfer(alice, first);
        vm.prank(alice);
        token.transfer(bob, second);
        assertEq(token.balanceOf(address(this)) + token.balanceOf(alice) + token.balanceOf(bob), SUPPLY);
        assertEq(token.balanceOf(alice), first - second);
        assertEq(token.balanceOf(bob), second);
        assertEq(token.totalSupply(), SUPPLY);
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_transferFromAboveBalanceWithInfiniteAllowanceReverts(uint256 balance, uint256 excess) public {
        balance = bound(balance, 0, SUPPLY);
        excess = bound(excess, 1, SUPPLY);
        token.transfer(alice, balance);
        vm.prank(alice);
        token.approve(spender, type(uint256).max);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, balance, balance + excess)
        );
        vm.prank(spender);
        token.transferFrom(alice, bob, balance + excess);
        assertEq(token.balanceOf(alice), balance);
        assertEq(token.allowance(alice, spender), type(uint256).max);
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_strangerCannotMoveOthersTokens(address stranger, uint256 amount) public {
        vm.assume(stranger != address(this));
        amount = bound(amount, 1, SUPPLY);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, stranger, 0, amount));
        vm.prank(stranger);
        token.transferFrom(address(this), stranger, amount);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }
}

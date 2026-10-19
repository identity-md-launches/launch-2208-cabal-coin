// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {CabalCoin} from "../src/CabalCoin.sol";

/// @dev Drives CabalCoin with unbounded amounts, so most calls are expected to fail. Every call is
///      checked against an independent model: a success must move exactly what the model says, a
///      failure must revert with the expected error and leave balances and allowances untouched.
///      The handler never reverts itself, so `fail_on_revert` stays meaningful.
contract CabalCoinAdversarialHandler is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 * 10 ** 18;

    CabalCoin internal immutable token;
    address[] internal actors;

    mapping(address => uint256) public expectedBalance;
    mapping(address => mapping(address => uint256)) public expectedAllowance;

    uint256 public ghostSucceeded;
    uint256 public ghostRejected;
    uint256 public ghostMoved;

    constructor(CabalCoin token_, address[] memory actors_) {
        token = token_;
        actors = actors_;
        expectedBalance[actors_[0]] = SUPPLY;
    }

    function actorCount() external view returns (uint256) {
        return actors.length;
    }

    function actorAt(uint256 i) external view returns (address) {
        return actors[i];
    }

    function _actor(uint256 seed) internal view returns (address) {
        return actors[seed % actors.length];
    }

    /// @dev Amounts cluster around the interesting edges: zero, the balance, one above it, the
    ///      supply, and the uint256 maximum, with an arbitrary value otherwise.
    function _amount(uint256 seed, uint256 edge) internal pure returns (uint256) {
        uint256 mode = seed % 6;
        if (mode == 0) return 0;
        if (mode == 1) return edge;
        if (mode == 2) return edge == type(uint256).max ? edge : edge + 1;
        if (mode == 3) return SUPPLY;
        if (mode == 4) return type(uint256).max;
        return seed >> 8;
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amountSeed) external {
        address from = _actor(fromSeed);
        address to = _actor(toSeed);
        uint256 balance = expectedBalance[from];
        uint256 amount = _amount(amountSeed, balance);

        if (amount > balance) {
            vm.expectRevert(
                abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, from, balance, amount)
            );
            vm.prank(from);
            token.transfer(to, amount);
            ++ghostRejected;
            return;
        }

        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        expectedBalance[from] -= amount;
        expectedBalance[to] += amount;
        ghostMoved += amount;
        ++ghostSucceeded;
        assertEq(token.balanceOf(from), expectedBalance[from]);
        assertEq(token.balanceOf(to), expectedBalance[to]);
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amountSeed) external {
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        uint256 amount = _amount(amountSeed, expectedBalance[owner]);
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        expectedAllowance[owner][spender] = amount;
        ++ghostSucceeded;
        assertEq(token.allowance(owner, spender), amount);
    }

    function transferFrom(uint256 fromSeed, uint256 toSeed, uint256 spenderSeed, uint256 amountSeed) external {
        address from = _actor(fromSeed);
        address to = _actor(toSeed);
        address spender = _actor(spenderSeed);
        uint256 allowance = expectedAllowance[from][spender];
        uint256 balance = expectedBalance[from];
        uint256 amount = _amount(amountSeed, amountSeed & 1 == 0 ? allowance : balance);

        // OpenZeppelin checks the allowance before the balance.
        if (amount > allowance) {
            vm.expectRevert(
                abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, allowance, amount)
            );
            vm.prank(spender);
            token.transferFrom(from, to, amount);
            ++ghostRejected;
            return;
        }
        if (amount > balance) {
            vm.expectRevert(
                abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, from, balance, amount)
            );
            vm.prank(spender);
            token.transferFrom(from, to, amount);
            ++ghostRejected;
            assertEq(token.allowance(from, spender), allowance);
            return;
        }

        vm.prank(spender);
        assertTrue(token.transferFrom(from, to, amount));
        expectedBalance[from] -= amount;
        expectedBalance[to] += amount;
        if (allowance != type(uint256).max) expectedAllowance[from][spender] = allowance - amount;
        ghostMoved += amount;
        ++ghostSucceeded;
        assertEq(token.allowance(from, spender), expectedAllowance[from][spender]);
    }

    function transferToZero(uint256 fromSeed, uint256 amountSeed) external {
        address from = _actor(fromSeed);
        uint256 amount = _amount(amountSeed, expectedBalance[from]);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(from);
        token.transfer(address(0), amount);
        ++ghostRejected;
    }

    function transferFromToZero(uint256 fromSeed, uint256 spenderSeed, uint256 amountSeed) external {
        address from = _actor(fromSeed);
        address spender = _actor(spenderSeed);
        uint256 allowance = expectedAllowance[from][spender];
        uint256 amount = _amount(amountSeed, allowance);
        if (amount > allowance) {
            vm.expectRevert(
                abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, allowance, amount)
            );
        } else {
            vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        }
        vm.prank(spender);
        token.transferFrom(from, address(0), amount);
        ++ghostRejected;
        assertEq(token.allowance(from, spender), allowance);
    }

    function transferFromZero(uint256 toSeed, uint256 spenderSeed, uint256 amountSeed) external {
        address to = _actor(toSeed);
        address spender = _actor(spenderSeed);
        uint256 amount = _amount(amountSeed, 0);
        if (amount == 0) {
            vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidApprover.selector, address(0)));
        } else {
            vm.expectRevert(
                abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, amount)
            );
        }
        vm.prank(spender);
        token.transferFrom(address(0), to, amount);
        ++ghostRejected;
    }

    function approveZeroSpender(uint256 ownerSeed, uint256 amountSeed) external {
        address owner = _actor(ownerSeed);
        uint256 amount = _amount(amountSeed, expectedBalance[owner]);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        vm.prank(owner);
        token.approve(address(0), amount);
        ++ghostRejected;
    }
}

contract CabalCoinAdversarialInvariantTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 10 ** 18;

    CabalCoin private token;
    CabalCoinAdversarialHandler private handler;

    function setUp() public {
        token = new CabalCoin();
        address[] memory actors = new address[](6);
        actors[0] = makeAddr("holder");
        actors[1] = makeAddr("trader");
        actors[2] = makeAddr("spender");
        actors[3] = makeAddr("stranger");
        // The deployer and the token's own address are actors too: neither may gain any power.
        actors[4] = address(this);
        actors[5] = address(token);
        token.transfer(actors[0], SUPPLY);
        handler = new CabalCoinAdversarialHandler(token, actors);

        bytes4[] memory selectors = new bytes4[](7);
        selectors[0] = CabalCoinAdversarialHandler.transfer.selector;
        selectors[1] = CabalCoinAdversarialHandler.approve.selector;
        selectors[2] = CabalCoinAdversarialHandler.transferFrom.selector;
        selectors[3] = CabalCoinAdversarialHandler.transferToZero.selector;
        selectors[4] = CabalCoinAdversarialHandler.transferFromToZero.selector;
        selectors[5] = CabalCoinAdversarialHandler.transferFromZero.selector;
        selectors[6] = CabalCoinAdversarialHandler.approveZeroSpender.selector;
        targetContract(address(handler));
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 64
    function invariant_balancesAndAllowancesMatchModel() public view {
        uint256 n = handler.actorCount();
        uint256 sum;
        for (uint256 i; i < n; ++i) {
            address a = handler.actorAt(i);
            uint256 balance = token.balanceOf(a);
            assertEq(balance, handler.expectedBalance(a));
            sum += balance;
            for (uint256 j; j < n; ++j) {
                address b = handler.actorAt(j);
                assertEq(token.allowance(a, b), handler.expectedAllowance(a, b));
            }
        }
        // Every token is held by an actor: nothing leaked to the zero address or anywhere else.
        assertEq(sum, SUPPLY);
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 64
    function invariant_supplyIsFixed() public view {
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.INITIAL_SUPPLY(), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(address(handler)), 0);
        assertEq(token.decimals(), 18);
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 64
    function invariant_zeroAddressNeverGainsAllowance() public view {
        uint256 n = handler.actorCount();
        for (uint256 i; i < n; ++i) {
            address a = handler.actorAt(i);
            assertEq(token.allowance(a, address(0)), 0);
            assertEq(token.allowance(address(0), a), 0);
        }
    }
}

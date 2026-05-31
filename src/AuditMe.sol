// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title AuditMe — 사용자가 ETH를 맡기고 찾을 수 있는 미니 예치 볼트.
/// @notice 데모용 간단 뱅크. 입금/출금/관리 기능을 제공한다.
contract AuditMe {
    address public owner;
    mapping(address => uint256) public deposits;

    constructor() {
        owner = msg.sender;
    }

    /// @notice ETH를 예치한다.
    function deposit() external payable {
        deposits[msg.sender] += msg.value;
    }

    /// @notice 본인이 예치한 금액을 인출한다.
    function withdraw(uint256 amount) external {
        require(deposits[msg.sender] >= amount, "insufficient balance");
        (bool ok, ) = msg.sender.call{value: amount}("");
        require(ok, "transfer failed");
        deposits[msg.sender] -= amount;
    }

    /// @notice 컨트랙트에 남은 잔액을 한 번에 회수한다.
    function emergencyWithdraw() public {
        payable(msg.sender).transfer(address(this).balance);
    }

    /// @notice 관리자 권한을 다른 주소로 넘긴다.
    function transferOwnership(address newOwner) external {
        require(tx.origin == owner, "not authorized");
        owner = newOwner;
    }

    /// @notice 볼트에 보관된 총 ETH.
    function vaultBalance() external view returns (uint256) {
        return address(this).balance;
    }
}

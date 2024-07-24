// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.0.0
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20FlashMint.sol";

contract EsRNTToken is
    ERC20,
    ERC20Burnable,
    Ownable,
    ERC20Permit,
    ERC20Votes,
    ERC20FlashMint
{
    // 存储每个地址的锁仓信息
    mapping(address => LockInfo) public lockInfo;
    struct LockInfo {
        uint256 lockedAmount; // 锁仓的esRNT数量
        uint256 releaseEnd; // 锁仓结束时间
    }

    constructor(
        address initialOwner
    )
        ERC20("esRNTToken", "esRNT")
        Ownable(initialOwner)
        ERC20Permit("esRNTToken")
    {}

    function mint(address to, uint256 amount) public onlyOwner {
        _mint(to, amount);
    }

    // The following functions are overrides required by Solidity.

    function _update(
        address from,
        address to,
        uint256 value
    ) internal override(ERC20, ERC20Votes) {
        super._update(from, to, value);
    }

    function nonces(
        address owner
    ) public view override(ERC20Permit, Nonces) returns (uint256) {
        return super.nonces(owner);
    }

    // 用户开始锁仓
    function lock(uint256 amount, uint256 duration) external {
        require(balanceOf(msg.sender) >= amount, "Insufficient balance");
        _transfer(msg.sender, address(this), amount); // 将代币从用户转移到合约本身
        lockInfo[msg.sender] = LockInfo({
            lockedAmount: amount,
            releaseEnd: block.timestamp + duration
        });
    }

    // 用户尝试释放锁仓的代币
    function release() external {
        LockInfo storage userLock = lockInfo[msg.sender];
        require(
            userLock.releaseEnd <= block.timestamp,
            "Lock period not ended"
        );

        uint256 releasableAmount = calculateReleasableAmount(userLock);
        if (releasableAmount > 0) {
            _transfer(address(this), msg.sender, releasableAmount);
            userLock.lockedAmount -= releasableAmount;
            if (userLock.lockedAmount == 0) {
                delete lockInfo[msg.sender];
            }
        }
    }

    // 计算当前可释放的esRNT数量
    function calculateReleasableAmount(
        LockInfo storage lockdata
    ) internal view returns (uint256) {
        if (block.timestamp >= lockdata.releaseEnd) {
            return lockdata.lockedAmount;
        } else {
            // 这里可以添加更复杂的线性释放逻辑
            return
                ((block.timestamp - lockdata.releaseEnd) *
                    lockdata.lockedAmount) / 30 days;
        }
    }
}

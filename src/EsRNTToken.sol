// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.0.0
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20FlashMint.sol";
import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "./RNTToken.sol";
import {Test, console} from "forge-std/Test.sol";

contract EsRNTToken is
    ERC20,
    ERC20Burnable,
    Ownable,
    ERC20Permit,
    ERC20Votes,
    ERC20FlashMint
{
    using SafeERC20 for RNTToken;
    RNTToken public _rntToken;

    address public stakePoolAddress;
    struct LockInfo {
        address user;
        uint256 amount;
        uint256 lockTime;
    }

    LockInfo[] public lockInfos;

    constructor(
        address rntTokenAddress
    )
        ERC20("esRNTToken", "esRNT")
        Ownable(msg.sender)
        ERC20Permit("esRNTToken")
    {
        _rntToken = RNTToken(rntTokenAddress);
    }

    function mintToken(address to, uint256 amount) public onlyOwner {
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

    function setOnlyOwner(address _newOwner) public onlyOwner {
        stakePoolAddress = _newOwner;
    }

    function mint(address to, uint256 amount) public {
        require(msg.sender == stakePoolAddress, "Only stake pool can mint");

        // 使用 SafeERC20 库确保 transferFrom 操作成功
        // https://medium.com/@JohnnyTime/why-you-should-always-use-safeerc20-94f44aa852d8
        // 对奖励部分进行锁仓操作
        _rntToken.safeTransferFrom(msg.sender, address(this), amount);

        // 调用内部函数进行铸造
        _mint(to, amount);

        // 记录锁定信息
        lockInfos.push(LockInfo(to, amount, block.timestamp));
    }

    function burn(uint256 id) public override {
        LockInfo memory lockData = lockInfos[id];
        require(lockData.user == msg.sender, "You are not the owner");

        // 计算解锁的时间比例
        uint256 timeElapsed = block.timestamp - lockData.lockTime;
        uint256 maxTime = 30 days; // 设置最大锁定时间为30天
        timeElapsed = (timeElapsed > maxTime) ? maxTime : timeElapsed;

        // 计算解锁的代币数量
        uint256 unLockedAmount = (lockData.amount * timeElapsed) / 30 days;
        // 转移解锁的代币给用户
        _rntToken.safeTransfer(lockData.user, unLockedAmount);

        // 燃烧剩余的代币
        uint256 burnAmount = lockData.amount - unLockedAmount;

        _rntToken.burn(burnAmount);
        // burn amount 是因为本次解锁的代币数量已经转移给用户，所以需要燃烧剩余的代币数量，因为剩余的已经没有用了
        _burn(msg.sender, lockData.amount);

        // 记录燃烧事件
        emit TokensBurned(lockData.user, burnAmount);

        // 从数组中移除锁定信息，这里使用 swap-and-pop 模式避免未初始化存储问题
        if (id < lockInfos.length - 1) {
            lockInfos[id] = lockInfos[lockInfos.length - 1];
        }
        lockInfos.pop();
    }

    function size() public view returns (uint) {
        return lockInfos.length;
    }

    // 燃烧事件
    event TokensBurned(address indexed user, uint256 amount);
}

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

contract EsRNTToken is
    ERC20,
    ERC20Burnable,
    Ownable,
    ERC20Permit,
    ERC20Votes,
    ERC20FlashMint
{
    using SafeERC20 for IERC20;

    IERC20 public _rntToken;

    // 存储每个地址的锁仓信息
    mapping(address => LockInfo) public lockInfo;
    struct LockInfo {
        address to;
        uint256 amount;
        uint256 timestamp;
    }

    LockInfo[] public lockInfos;

    constructor(
        address initialOwner,
        address rntTokenAddress
    )
        ERC20("esRNTToken", "esRNT")
        Ownable(initialOwner)
        ERC20Permit("esRNTToken")
    {
        _rntToken = IERC20(rntTokenAddress);
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

    function mint(address to, uint256 amount) public onlyOwner {
        // 使用 SafeERC20 库确保 transferFrom 操作成功
        // https://medium.com/@JohnnyTime/why-you-should-always-use-safeerc20-94f44aa852d8
        _rntToken.safeTransferFrom(msg.sender, address(this), amount);

        // 调用内部函数进行铸造
        _mint(to, amount);

        // 记录锁定信息
        lockInfos.push(LockInfo(to, amount, block.timestamp));
    }
}

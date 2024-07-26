// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.20;

import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "@openzeppelin/contracts/mocks/EIP712Verifier.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "./EsRNTToken.sol";

// 质押挖矿合约 Staking Mining Contract
// 用户随时可以质押项目方代币 RNT(自定义的ERC20) ，开始赚取项目方Token(esRNT)；
// 可随时解押提取已质押的 RNT；
// 可随时领取esRNT奖励，每质押1个RNT每天可奖励 1 esRNT;
// esRNT 是锁仓性的 RNT， 1 esRNT 在 30 天后可兑换 1 RNT，随时间线性释放，支持提前将 esRNT 兑换成 RNT，但锁定部分将被 burn 燃烧掉。

// 经济模型 一部分IDO 一部分质押
// 100 亿 RNT 5 亿 IDO 15 亿 质押
contract StakingRewards is Ownable(msg.sender), EIP712Verifier {
    // RNT 代币合约地址
    IERC20 public rntToken;
    // esRNT 代币合约地址
    EsRNTToken public esRntToken;

    string private constant SIGNING_DOMAIN = "StakingRewards";
    string private constant SIGNATURE_VERSION = "1";

    // 每天奖励的esRNT数量
    uint256 public constant DAILY_REWARDS = 1e18;

    struct StakeInfo {
        uint256 stakedAmount;
        uint256 lastUpdateTime;
        uint256 unClaimed;
    }

    mapping(address => StakeInfo) public staked;

    constructor(
        address _erc20,
        address _esRntToken
    ) EIP712(SIGNING_DOMAIN, SIGNATURE_VERSION) {
        require(_erc20 != address(0), "zero address");
        require(_esRntToken != address(0), "zero address");
        rntToken = IERC20(_erc20);
        esRntToken = EsRNTToken(_esRntToken);
        rntToken.approve(address(esRntToken), type(uint256).max);
    }

    /**
     *
     * @param amount The amount of tokens to stake
     * Before staking, you must first Approve the staking pool contract
     * 2612 permit 签名
     * @dev Stake RNT tokens
     *
     */
    function stake(uint256 amount) public {
        require(amount > 0, "Amount must be greater than zero");

        _calculateRewards(msg.sender);
        staked[msg.sender].stakedAmount += amount;

        // 10:00 Alice 10RNT
        // 转移RNT代币到合约地址
        // Transfer RNT tokens from the user to the contract
        rntToken.transferFrom(msg.sender, address(this), amount);
        emit Staked(msg.sender, amount);
    }

    function permitStake(
        uint256 amount,
        uint256 deadline,
        bytes memory permit2612Signature
    ) external {
        require(amount > 0, "Amount must be greater than zero");
        require(
            permit2612Signature.length == 65,
            "signature must be 65 bytes long"
        );

        // https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/utils/cryptography/ECDSA.sol
        // (uint8 v, bytes32 r, bytes32 s) = abi.decode(signature, (uint8, bytes32, bytes32));
        bytes32 r;
        bytes32 s;
        uint8 v;
        // ecrecover takes the signature parameters, and the only way to get them
        // currently is to use assembly.
        /// @solidity memory-safe-assembly
        assembly {
            r := mload(add(permit2612Signature, 0x20))
            s := mload(add(permit2612Signature, 0x40))
            v := byte(0, mload(add(permit2612Signature, 0x60)))
        }

        // 使用 IERC20Permit 的 permit 方法进行代币授权。 token.permit
        IERC20Permit(address(rntToken)).permit(
            msg.sender,
            address(this),
            amount,
            deadline,
            v,
            r,
            s
        );
        stake(amount);
    }

    function unstake(uint256 amount) external {
        require(amount > 0, "Amount must be greater than zero");

        StakeInfo storage stakeInfo = staked[msg.sender];
        require(stakeInfo.stakedAmount >= amount, "Insufficient staked amount");
        require(
            rntToken.balanceOf(address(this)) >= amount,
            "Insufficient RNT balance"
        );

        _calculateRewards(msg.sender);
        stakeInfo.stakedAmount -= amount;

        // 将RNT代币返回给用户
        rntToken.transfer(msg.sender, amount);
        emit Unstaked(msg.sender, amount);
    }

    // 领取奖励
    function claim() external {
        _calculateRewards(msg.sender);
        StakeInfo storage stakeInfo = staked[msg.sender];

        uint256 rewards = stakeInfo.unClaimed;
        require(rewards > 0, "No rewards to claim");

        stakeInfo.unClaimed = 0;
        // rntToken.approve(address(esRntToken), rewards);

        esRntToken.mint(msg.sender, rewards);
        emit RewardClaimed(msg.sender, rewards);
    }

    function getUnclaimedRewards(
        address account
    ) public view returns (uint256) {
        // 从映射中获取质押信息
        StakeInfo memory stakeInfo = staked[account];

        // 计算自上次更新以来经过的天数
        uint256 daysPassed = (block.timestamp - stakeInfo.lastUpdateTime) /
            1 days;

        // 计算未领取的奖励
        uint256 rewards = ((daysPassed * stakeInfo.stakedAmount) *
            DAILY_REWARDS) / 1e18;

        // 返回未领取的奖励加上之前未领取的奖励
        return stakeInfo.unClaimed + rewards;
    }

    function _calculateRewards(address stakedAccount) internal {
        StakeInfo storage stakeInfo = staked[stakedAccount];
        if (stakeInfo.lastUpdateTime == 0) {
            stakeInfo.lastUpdateTime = block.timestamp;
            return;
        }

        uint256 daysPassed = (block.timestamp - stakeInfo.lastUpdateTime) /
            1 days;
        stakeInfo.unClaimed +=
            (daysPassed * stakeInfo.stakedAmount * DAILY_REWARDS) /
            1e18;

        stakeInfo.lastUpdateTime = block.timestamp;
    }

    event Staked(address indexed user, uint256 amount);
    event Unstaked(address indexed user, uint256 amount);
    event RewardClaimed(address indexed user, uint256 reward);
}

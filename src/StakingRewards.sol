// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.20;

import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "@openzeppelin/contracts/mocks/EIP712Verifier.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";

// 质押挖矿合约
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
    IERC20 public esRntToken;

    string private constant SIGNING_DOMAIN = "StakingRewards";
    string private constant SIGNATURE_VERSION = "1";

    // 每天奖励的esRNT数量
    uint256 public constant DAILY_REWARDS = 1e18;

    // 质押奖励的结束时间
    uint256 public endTimestamp;

    // 记录每个用户的最后质押时间
    mapping(address => uint256) public lastStakedTime;
    // 质押池
    mapping(address => uint256) public staked;
    // 用户领取奖励
    mapping(address => uint256) public claimed;

    constructor(
        address _erc20,
        address _esRntToken
    ) EIP712(SIGNING_DOMAIN, SIGNATURE_VERSION) {
        require(_erc20 != address(0), "zero address");
        rntToken = IERC20(_erc20);
        esRntToken = IERC20(_esRntToken);
    }

    /**
     *
     * @param amount The amount of tokens to stake
     * 质押前首先要 Approve 授权质押池合约
     * 2612 permit 签名
     * @dev Stake RNT tokens
     *
     */
    function stake(uint256 amount) external {
        require(amount > 0, "Amount must be greater than zero");
        // 更新用户的质押时间和数量
        lastStakedTime[msg.sender] = block.timestamp;
        staked[msg.sender] += amount;

        endTimestamp = block.timestamp + 30 days;
        // 计算用户的奖励
        uint256 rewards = calculateRewards(lastStakedTime[msg.sender], amount);
        // 领取奖励
        claimed[msg.sender] += rewards;

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

        // 使用 IERC20Permit 的 permit 方法进行代币授权。
        IERC20Permit(address(rntToken)).permit(
            msg.sender,
            address(this),
            amount,
            deadline,
            v,
            r,
            s
        );

        // 更新用户的质押时间和数量
        lastStakedTime[msg.sender] = block.timestamp;
        staked[msg.sender] += amount;

        endTimestamp = block.timestamp + 30 days;
        // 计算用户的奖励
        uint256 rewards = calculateRewards(lastStakedTime[msg.sender], amount);
        // 领取奖励
        claimed[msg.sender] += rewards;

        rntToken.transferFrom(msg.sender, address(this), amount);
        emit Staked(msg.sender, amount);
    }

    function unstake(uint256 amount) external {
        require(staked[msg.sender] >= amount, "Insufficient staked amount");
        // 更新用户的质押记录
        staked[msg.sender] -= amount;
        // 删除用户的质押时间记录
        delete lastStakedTime[msg.sender];
        // 将RNT代币返回给用户
        rntToken.transfer(msg.sender, amount);
        emit Unstaked(msg.sender, amount);
    }

    // 领取奖励
    function claim() external {
        uint256 stakeTime = lastStakedTime[msg.sender];
        require(stakeTime > 0, "No stake time recorded");

        uint256 rewards = calculateRewards(stakeTime, staked[msg.sender]);
        require(rewards > 0, "No rewards to claim");
        require(
            esRntToken.transfer(msg.sender, rewards),
            "Failed to transfer rewards"
        );

        // 更新已领取的奖励
        claimed[msg.sender] += rewards;
        emit RewardClaimed(msg.sender, rewards);
    }

    // esRNT 兑换成 RNT
    function redeem(uint256 amount) external {
        require(block.timestamp >= endTimestamp, "Staking period not ended");
        require(amount <= claimed[msg.sender], "Insufficient claimed rewards");
        // 更新已领取的奖励
        claimed[msg.sender] -= amount;

        // 将esRNT代币转给合约
        esRntToken.transferFrom(msg.sender, address(this), amount);

        // 将RNT代币返回给用户
        rntToken.transfer(msg.sender, amount);
        emit Redeemed(msg.sender, amount);
    }

    // 计算奖励
    function calculateRewards(
        uint256 stakeTime,
        uint256 stakedAmount
    ) internal view returns (uint256) {
        // 计算从质押时间到当前时间的天数
        uint256 daysPassed = (block.timestamp - stakeTime) / 1 days;
        // 计算总奖励
        return (daysPassed * stakedAmount * DAILY_REWARDS) / 1e18;
    }

    event Staked(address indexed user, uint256 amount);
    event Unstaked(address indexed user, uint256 amount);
    event RewardClaimed(address indexed user, uint256 reward);
    event Redeemed(address indexed user, uint256 amount);
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

abstract contract ReentrancyGuard {

    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;

    uint256 private _status;

    constructor() {
        _status = _NOT_ENTERED;
    }

    modifier nonReentrant() {
        require(_status != _ENTERED, "ReentrancyGuard: reentrant call");
        _status = _ENTERED;
        _;
        _status = _NOT_ENTERED;
    }
}

interface IDatabase {
    function users(address user) external view returns (
        uint256 userId,
        address referrer,
        uint64 inviteCode,
        uint256 vipLevel,
        bool activated,
        uint256 balance,
        uint256 pendingReward,
        uint256 pendingToken,
        uint256 teamSize,
        uint256 activeTeamSize,
        uint256 directPerformance,
        uint256 teamPerformance,
        uint256 teamRevenue,
        uint256 donateTimestamp
    );
    function registerUser(address user, uint64 referrerCode) external;
    function activateUser(address userAddress) external;
    function donate(address user) external;
    function claimDonationReward(address user) external;
    function isRegistered(address user) external view returns (bool);
}

contract PaymentContract is ReentrancyGuard {
    address public DATABASE;

    event Deposit(address indexed user, uint256 amount);

    modifier onlyEOA() {
        require(msg.sender == tx.origin, "Caller is not EOA");
        _;
    }

    constructor(address _database) {
      DATABASE = _database;
    }

    receive() external payable nonReentrant onlyEOA {
        IDatabase db = IDatabase(DATABASE);
        address user = msg.sender;
    
        if (msg.value == 0.02 ether) {
            _handleActivate(db, user);
        } else if (msg.value == 0.03 ether) {
            _handleDonate(db, user);
        } else if (msg.value == 0.005 ether) {
            _handleClaimReward(db, user);
        } else {
            emit Deposit(user, msg.value);
        }
    }
    
    fallback() external payable nonReentrant onlyEOA{
        IDatabase db = IDatabase(DATABASE);
        address user = msg.sender;
    
        if (msg.value == 0.01 ether) {
            _handleRegister(db, user); // 推荐码处理逻辑
        } else {
            revert("Invalid amount");
        }
    }

    /// @dev 注册用户逻辑
    function _handleRegister(IDatabase db, address user) internal {
        require(msg.data.length >= 8, "Invalid referrer code"); // uint64 = 8字节
        bytes8 asciiData;
        assembly {
            asciiData := calldataload(0)
        }
        uint64 referrerCode = _asciiToUint(asciiData);
    
        require(referrerCode >= 100000 && referrerCode <= 999999, "Invalid code");

        require(!db.isRegistered(user), "Already registered");
        db.registerUser(user, referrerCode);

        // 注册成功返 0.005 ETH
        (bool refundSuccess, ) = payable(user).call{value: 0.005 ether}("");
        require(refundSuccess, "Refund failed");
    }

    /// @dev 激活逻辑
    function _handleActivate(IDatabase db, address user) internal {
        require(db.isRegistered(user), "User not registered");
        db.activateUser(user);

        // ✅ 激活成功后返还 0.01 ETH 并附带用户信息
        uint256 rewardAmount = 0.01 ether;
        require(address(this).balance >= rewardAmount, "Insufficient contract balance");

        _sendWithNote(user, rewardAmount);
    }

    /// @dev 捐赠逻辑（需要激活）
    function _handleDonate(IDatabase db, address user) internal {
        require(db.isRegistered(user), "User not registered");
        (, , , , bool activated,,,,,,,,,) = db.users(user);
        require(activated, "User not activated");
        db.donate(user);
    }

    /// @dev 领取捐赠奖励逻辑
    function _handleClaimReward(IDatabase db, address user) internal {
        require(db.isRegistered(user), "User not registered");

        // 读取用户信息，取 donateTimestamp
        (
            , , , , , , , , , , , , , uint256 donateTimestamp
        ) = db.users(user);

        // 确保用户捐赠过
        require(donateTimestamp != 0, "No donation record");

        // 计算时间差
        uint256 timeDiff = block.timestamp - donateTimestamp;
        require(timeDiff >= 1 days, "Cannot claim within 1 day after donation"); // 至少 24 小时后才能领取

        // 计算奖励金额：<=3 天返 2 ETH，否则返 1 ETH
        uint256 amount = (timeDiff <= 3 days) ? 0.025 ether : 0.015 ether;
        require(address(this).balance >= amount, "Insufficient contract balance");

        // 调用 Database 标记已领取
        db.claimDonationReward(user);

        // 返还奖励金额并附带用户信息 Note
        _sendWithNote(user, amount);
    }

    /// @dev 给用户发奖励 + 附带 Note 信息
    function _sendWithNote(address user, uint256 amount) internal {
        (
            , , uint64 inviteCode, uint256 vipLevel, , uint256 balance, uint256 pendingReward,
            uint256 pendingToken, uint256 teamSize, uint256 activeTeamSize,
            uint256 directPerformance, uint256 teamPerformance, , uint256 donateTimestamp
        ) = IDatabase(DATABASE).users(user);

        uint256 expireTimestamp = donateTimestamp + 3 days;

        string memory note = string(
            abi.encodePacked(
                unicode"等级:V", _uintToString(vipLevel), "\n",
                unicode"邀请码:", _uintToString(inviteCode), "\n",
                unicode"余额:", _uintToString(balance), "\n",
                unicode"未领收益:", _uintToString(pendingReward), "\n",
                unicode"未领代币:", _uintToString(pendingToken), "\n",
                unicode"团队人数:", _uintToString(teamSize), "/", _uintToString(activeTeamSize), "\n",
                unicode"直推业绩:", _uintToString(directPerformance), "\n",
                unicode"团队业绩:", _uintToString(teamPerformance), "\n",
                unicode"最近捐赠:", _uintToString(donateTimestamp), "\n",
                unicode"有效期:", _uintToString(expireTimestamp)
            )
        );

        (bool success, ) = payable(user).call{value: amount}(bytes(note));
        require(success, "Reward transfer failed");
    }

    /// @dev 工具函数1
    function _uintToString(uint256 value) internal pure returns (string memory) {
        if (value == 0) return "0";
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) { digits++; temp /= 10; }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }

    /// @dev 工具函数2
    function _asciiToUint(bytes8 data) internal pure returns (uint64) {
        uint64 num = 0;
        for (uint i = 0; i < 8; i++) {
            uint8 b = uint8(data[i]);
            if (b == 0) break; // padding 停止
            require(b >= 48 && b <= 57, "Non-digit"); // 必须是数字
            num = num * 10 + (b - 48);
        }
        return num;
    }

}

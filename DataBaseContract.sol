pragma solidity 0.8.24;
// SPDX-License-Identifier: MIT

contract DataBaseContract {
    
    // 用户数据
    struct UserInfo {
        uint256 userId; // 用户编号
        address referrer; // 推荐人地址
        uint64 inviteCodeNum; // 用户的邀请码
        uint256 vipLevel; // VIP级别
        bool activated; // 是否激活过
        uint256 balance; // 可用余额
        uint256 pendingReward; // 用户未领取收益
        uint256 pendingToken; // 用户未领取的代币数量
        uint256 teamSize; // 注册团队人数
        uint256 activeTeamSize; // 有效团队人数（统计捐赠过的人数）
        uint256 directPerformance; // 直推总业绩（直推总激活金额）
        uint256 teamPerformance; // 团队总业绩（团队总激活金额）
        uint256 teamRevenue; // 团队流水收益（团队总捐赠利润）
        uint256 donateTimestamp; // 最近一次捐赠时间戳
    }

    // 注册订单
    struct RegisterOrder {
        uint256 orderId;
        address user;
        address referrer;
        uint256 timestamp;
    }

    // 激活订单
    struct ActivateOrder {
        uint256 orderId;
        address user;
        uint256 timestamp;
    }

    // 捐赠订单
    struct DonateOrder {
        uint256 orderId;
        address user;
        bool isFirstDonation;
        uint256 timestamp;
    }

    address owner; // 合约所有者
    address public systemReferrer = 0xaf07DCE2B9A6E056AB9C9E6B85723c064b7D7959; // 系统地址

    mapping(address => UserInfo) public users; // 用户映射表
    mapping(uint64 => address) public codeToUser; // 邀请码映射表

    mapping(uint256 => RegisterOrder) public registerOrders; // 注册订单映射表
    mapping(uint256 => ActivateOrder) public activateOrders; // 激活订单映射表
    mapping(uint256 => DonateOrder) public donateOrders; // 捐赠订单映射表

    mapping(address => uint256) public directActiveCount; // 记录每个用户的直推有效数量
    mapping(address => bool) public donationClaimed; // 记录用户是否已领取捐赠收益

    mapping(address => bool) public allowedCallers; // 允许调用者列表
    address[] public allowedCallerList; // 允许调用者数组

    uint256 public baseProfitUnit = 100; // 捐赠利润

    uint256 public nextUserId = 2; // 下一个用户 id
    uint256 public nextOrderId = 1; // 下一个注册订单 id
    uint256 public nextActivateOrderId = 1; // 下一个激活订单 id
    uint256 public nextDonateOrderId = 1; // 下一个捐赠订单 id

    event Registered(address indexed user, address indexed referrer, uint256 orderId, uint256 timestamp); // 注册
    event Activated(address indexed user, uint64 inviteCodeNum, uint256 orderId, uint256 timestamp); // 激活
    event Donated(address indexed user, uint256 orderId, uint256 timestamp); // 捐赠
    event DonationRewardClaimed(address indexed user, uint256 timestamp); // 领取捐赠收益
    event AllowedCallerUpdated(address caller, bool allowed); // 白名单变更

    constructor() {
        owner = msg.sender;
        users[systemReferrer] = UserInfo({
            userId: 1,
            referrer: address(0),
            inviteCodeNum: 100000,
            vipLevel: 10,
            activated: true,
            balance: 100000000,
            pendingReward: 0,
            pendingToken: 0,
            teamSize: 0,
            activeTeamSize: 0,
            directPerformance: 0,
            teamPerformance: 0,
            teamRevenue: 0,
            donateTimestamp: 0
        });

        codeToUser[100000] = systemReferrer;

        emit Registered(systemReferrer, address(0), 0, block.timestamp);
        emit Activated(systemReferrer, 100000, 0, block.timestamp);
    }

    modifier onlyOwner() {
		require(msg.sender == owner, "Not owner");
		_;
	}

    function changeOwner(address _newOwner) public onlyOwner {
		owner = _newOwner;
	}

    // 注册（绑定推荐码）
    function registerUser(address user, uint64 referrerCode) external {
        require(allowedCallers[msg.sender], "Not authorized caller");
        require(users[user].userId == 0, "Already registered");
        
        address referrer = codeToUser[referrerCode];
        require(referrer != address(0), "Referrer code not found");
        require(referrer != user, "Cannot refer yourself");

        users[user] = UserInfo({
            userId: nextUserId,
            referrer: referrer,
            inviteCodeNum: 0,
            vipLevel: 0,
            activated: false,
            balance: 0,
            pendingReward: 0,
            pendingToken: 0,
            teamSize: 0,
            activeTeamSize: 0,
            directPerformance: 0,
            teamPerformance: 0,
            teamRevenue: 0,
            donateTimestamp: 0
        });

        // 生成注册订单并记录
        uint256 currentOrderId = nextOrderId;
        registerOrders[currentOrderId] = RegisterOrder({
            orderId: currentOrderId,
            user: user,
            referrer: referrer,
            timestamp: block.timestamp
        });

        nextOrderId++;
        nextUserId++;

        emit Registered(user, referrer, currentOrderId, block.timestamp);
    }

    // 激活（生成唯一邀请码）
    function activateUser(address userAddress) external {
        require(allowedCallers[msg.sender], "Not authorized caller");

        UserInfo storage user = users[userAddress];
        require(user.userId != 0, "Not registered");

        // 首次激活：生成邀请码
        if (!user.activated) {
            uint64 inviteCode;
            bool unique = false;

            for (uint8 i = 0; i < 10; i++) {
                uint256 random = uint256(keccak256(
                    abi.encodePacked(userAddress, block.timestamp, user.userId, i)
                )) % 900000 + 100000; // 保证 6 位数字 (100000 - 999999)

                inviteCode = uint64(random);

                if (codeToUser[inviteCode] == address(0)) {
                    unique = true;
                    break;
                }
            }

            require(unique, "Invite code generation failed");

            user.inviteCodeNum = inviteCode; // 用 uint64 存储
            user.activated = true;
            codeToUser[inviteCode] = userAddress;
        }

        user.balance += 6000;

        // 生成激活订单
        uint256 currentOrderId = nextActivateOrderId;
        activateOrders[currentOrderId] = ActivateOrder({
            orderId: currentOrderId,
            user: userAddress,
            timestamp: block.timestamp
        });

        emit Activated(userAddress, user.inviteCodeNum, currentOrderId, block.timestamp);
        nextActivateOrderId++;
    }

    // 捐赠 （用户打流水）
    function donate(address user) external {
        require(allowedCallers[msg.sender], "Not authorized caller");
        require(users[user].activated, "User not activated");

        bool firstDonation = (users[user].donateTimestamp == 0);

        if (firstDonation) {
            // 首次捐赠逻辑
            address referrer = users[user].referrer;
            if (referrer != address(0)) {
                directActiveCount[referrer] += 1;
            }
        } else {
            // 非首次捐赠逻辑
            require(donationClaimed[user], "Previous reward not claimed");
        }

        users[user].donateTimestamp = block.timestamp;
        donationClaimed[user] = false;
        
        // 创建捐赠订单
        uint256 currentOrderId = nextDonateOrderId;
        donateOrders[currentOrderId] = DonateOrder({
            orderId: currentOrderId,
            user: user,
            isFirstDonation: firstDonation,
            timestamp: block.timestamp
        });

        emit Donated(user, currentOrderId, block.timestamp);

        nextDonateOrderId++;
    }

    // 领取捐赠收益
    function claimDonationReward(address user) external {
        require(allowedCallers[msg.sender], "Not authorized caller");
        require(users[user].userId != 0, "User not registered");
        require(users[user].activated, "User not activated");
        require(users[user].donateTimestamp != 0, "No donation record");
        require(!donationClaimed[user], "Reward already claimed");
        require(block.timestamp >= users[user].donateTimestamp + 1 days, "Cannot claim within 1 day after donation");
        
        donationClaimed[user] = true;

        emit DonationRewardClaimed(user, block.timestamp);
    }

    // 根据 activeTeamSize 计算 VIP 等级
    function _calculateVIP(uint256 activeSize) internal pure returns (uint256) {
        if (activeSize >= 300000) return 10;
        if (activeSize >= 100000) return 9;
        if (activeSize >= 30000)  return 8;
        if (activeSize >= 10000)  return 7;
        if (activeSize >= 3000)   return 6;
        if (activeSize >= 1000)   return 5;
        if (activeSize >= 300)    return 4;
        if (activeSize >= 100)    return 3;
        if (activeSize >= 30)     return 2;
        if (activeSize >= 10)     return 1;
        return 0;
    }

    // 级差比例表
    function _vipRewardPercent(uint256 vipLevel) internal pure returns (uint256) {
        if (vipLevel == 1) return 5;
        if (vipLevel == 2) return 10;
        if (vipLevel == 3) return 15;
        if (vipLevel == 4) return 20;
        if (vipLevel == 5) return 25;
        if (vipLevel == 6) return 30;
        if (vipLevel == 7) return 35;
        if (vipLevel == 8) return 40;
        if (vipLevel == 9) return 45;
        if (vipLevel == 10) return 50;
        return 0;
    }

    // 查询用户是否注册过
    function isRegistered(address user) external view returns (bool) {
        return users[user].userId != 0;
    }

    // 读取所有白名单地址
    function getAllAllowedCallers() external view returns (address[] memory) {
        return allowedCallerList;
    }

    // 管理员管理可调用合约白名单
    function setAllowedCaller(address caller, bool allowed) external onlyOwner {
        bool current = allowedCallers[caller];

        if (allowed && !current) {
            // 添加新白名单地址
            allowedCallers[caller] = true;
            allowedCallerList.push(caller);
        } else if (!allowed && current) {
            // 从白名单中移除
            allowedCallers[caller] = false;

            // 移除数组中的地址
            for (uint256 i = 0; i < allowedCallerList.length; i++) {
                if (allowedCallerList[i] == caller) {
                    allowedCallerList[i] = allowedCallerList[allowedCallerList.length - 1];
                    allowedCallerList.pop();
                    break;
                }
            }
        }

        emit AllowedCallerUpdated(caller, allowed);
    }

    // 管理员更新注册团队人数
    function updateTeamSize(uint256 orderId) external onlyOwner {
        RegisterOrder memory order = registerOrders[orderId];
        require(order.user != address(0), "Invalid order ID");

        address currentReferrer = order.referrer;

        // 向上遍历推荐链
        while (currentReferrer != address(0)) {
            users[currentReferrer].teamSize += 1;
            currentReferrer = users[currentReferrer].referrer;
        }
    }

    // 管理员更新动态奖
    function processActivationReward(uint256 orderId) external onlyOwner {
        ActivateOrder memory order = activateOrders[orderId];
        require(order.user != address(0), "Invalid order ID");
    
        address currentReferrer = users[order.user].referrer;
        uint256 level = 1;
    
        while (currentReferrer != address(0)) {
            if (level <= 31) {
                if (level == 1) {
                    // 第一代：直推奖 600
                    users[currentReferrer].pendingReward += 600; 
                    users[currentReferrer].directPerformance += 2000;
                } else {
                    // 从第二代开始，判断是否能拿代数奖
                    uint256 directCount = directActiveCount[currentReferrer];
                    uint256 maxGeneration = 0;
    
                    if (directCount >= 3) {
                        maxGeneration = 30;
                    } else if (directCount == 2) {
                        maxGeneration = 20;
                    } else if (directCount == 1) {
                        maxGeneration = 10;
                    }
    
                    if (level <= maxGeneration) {
                        users[currentReferrer].pendingReward += 20; // 代数奖 1%
                    }
                }
            }
    
            users[currentReferrer].teamPerformance += 2000;
            currentReferrer = users[currentReferrer].referrer;
            level++;
        }
    }

    // 管理员更新团队流水收益&VIP级别&级差奖
    function updateTeamRevenueAndReward(uint256 orderId) external onlyOwner {
        DonateOrder memory order = donateOrders[orderId];
        require(order.user != address(0), "Invalid order ID");
    
        address currentReferrer = users[order.user].referrer;
        uint256 distributedPercent = 0;
        uint256 lastVipLevel = 0;
    
        while (currentReferrer != address(0)) {
            UserInfo storage u = users[currentReferrer];
    
            u.teamRevenue += baseProfitUnit;
    
            // 首次捐赠 -> 更新有效人数 & VIP等级
            if (order.isFirstDonation) {
                u.activeTeamSize += 1;
    
                uint256 newVIP = _calculateVIP(u.activeTeamSize);
                if (newVIP > u.vipLevel) {
                    u.vipLevel = newVIP;
                }
            }
    
            // 级差逻辑：只给第一个更高VIP的用户差额奖励
            if (u.vipLevel > lastVipLevel) {
                uint256 maxPercent = _vipRewardPercent(u.vipLevel);
                if (maxPercent > distributedPercent) {
                    uint256 diffPercent = maxPercent - distributedPercent;
                    uint256 reward = (baseProfitUnit * diffPercent) / 100;
    
                    u.pendingReward += reward;
                    distributedPercent = maxPercent;
                    lastVipLevel = u.vipLevel;
                }
            }
    
            // 如果已经达到最高比例（比如50%），提前结束
            if (distributedPercent >= 50) break;
    
            currentReferrer = u.referrer;
        }
    }
}

/// SPDX-License-Identifier: MIT-0
pragma solidity >=0.7.3 <0.9.0;

import "hardhat/console.sol";

contract Registrar {
    event Locked(string indexed name, address indexed sender, uint256 expiry);
    event Registered(
        string indexed name,
        address indexed sender,
        uint256 expiry
    );

    uint256 gasRequiredForLock = 28000000;
    uint256 expiryMinutes = 300; // 5 minutes
    uint256 registeredExpiryMinutes = 3.156e7; // 1 year
    mapping(string => address) lockMapping;
    mapping(string => mapping(address => uint256)) lockExpiryMapping;

    mapping(string => address) registeredMapping;
    mapping(string => mapping(address => uint256)) registeredLockAmountMapping;
    mapping(string => mapping(address => uint256)) registeredExpiryMapping;

    address admin;

    constructor() {
        admin = msg.sender;
    }

    /**
        This is a pre-commitment scheme to avoid front-running as recommended here -> 
        https://s3.amazonaws.com/ieeecs.cdn.csdl.content/trans/ts/5555/01/09555611.pdf?AWSAccessKeyId=ASIA2Z6GPE73JPHMV3MX&Expires=1643384177&Signature=FMIcwPXV2LdvY49nN4TvK41L7E4%3D&x-amz-security-token=IQoJb3JpZ2luX2VjEK7%2F%2F%2F%2F%2F%2F%2F%2F%2F%2FwEaCXVzLWVhc3QtMSJGMEQCICnlKTf%2BUi8sqxrt9XhQwCn0x8v5O1efI%2BHnreumMUt2AiAGGw7GzNcHangqiuK4%2Bz3tO57MPpfF43gJRXYfodQYJyqmAgjX%2F%2F%2F%2F%2F%2F%2F%2F%2F%2F8BEAAaDDc0MjkwODcwMDY2MiIMV1ZLxdoDHUPNtD%2BTKvoB59IWUNPH753cyxFcEM6GMGmdF2fnPduk8IRKQsicpS3FdEHYMNjRjkzWzs9XK8D9gOUXXmiSeeraY7b3EJR4l5Smk%2BCToARTY2asaMRfR%2BCGXkx5VI3lxYr76EMFgrw%2BxBFQJbBodbHp1iYYbmp9A%2Fr8ec1RQVbmbY5XuWDetf4T72ZTFDZ6IP0HmKs4lSlTIn%2FWWGqWie2qGL%2B%2FTzzHu%2F5PvbAcetSQnlH0fVlWQC6fOHg4M%2Fm4IbOmgOvPnDSjV6zGp8Qj39wTpiQ2BxNvKxmjNecrgQWleYo98cuJkzCG8pZjjZ3YRBY9PFe4KPs24XCufwt37FQquTC37c%2BPBjqbAZx7OVwaNw7dsgqOWRERLch3YlvPEie2mT%2FbbP605tGxHRQ9g5Mqf%2F9Yz197trYN6ZFSC32Y7DBbSLTGbTd9%2Fj7ijm5nceTL0acolpNhV9EghkizcqJU8pnTjIhJLHPHaBn2aySh8z5Gi7h%2FGtGsLFoo%2FbRsQIT4hVKDFUc9fEYrnm73auM9YmMw7IIXJNZL06M2FOtzV%2BTmh9U8

        Basically, a user first announces they want to register a name and this annoucement is locked in before the actual
        call to registration. A Malicious node can see the announcement and make it before the user,
        We can then employ another method to prevent front-running. 
            
        We can safely calculate the gas required before hand, we can check that the gas fees
        sent is not higher than X, where X is what is required to send the transaction successfully.

        Announcements will expire after Y minutes
     */
    function lock(string memory name) public {
        require(
            gasleft() <= gasRequiredForLock,
            "Gas too high. Front-running not allowed"
        );

        require(
            registeredMapping[name] == address(0),
            "Name already registered"
        );

        address sender = msg.sender;
        bool canLock = false;
        uint256 lockExpiry = lockExpiryMapping[name][sender];

        if (lockExpiry > 0) {
            // has it expired ?
            if (lockExpiry < block.timestamp) {
                canLock = true;
            } else {
                canLock = false;
            }
        } else {
            address locker = lockMapping[name];
            lockExpiry = lockExpiryMapping[name][locker];
            if(lockExpiry < block.timestamp) {
                // lock has expired
                canLock = true;
            } else {
                canLock = false;
            }
        }

        if (canLock) {
            lockExpiryMapping[name][sender] = block.timestamp + expiryMinutes;
            lockMapping[name] = sender;
        } else {
            revert("Can not lock. Front-running not allowed");
        }

        emit Locked(name, sender, lockExpiryMapping[name][sender]);
    }

    // gets the price of registring a name
    function calculatePrice(string memory name) public pure returns (uint256) {
        return bytes(name).length; // in wei
    }

    modifier checkLock(string memory name, address sender) {
        require(
            lockExpiryMapping[name][sender] > 0,
            "No lock found for name/sender pair"
        );

        require(
            lockExpiryMapping[name][sender] > block.timestamp,
            "Lock expired"
        );

        require(lockMapping[name] == sender, "Name locked by another user");

        _;
    }

    function registerName(string memory name)
        public
        payable
        checkLock(name, msg.sender)
    {
        address sender = msg.sender;

        uint256 registrationCost = bytes(name).length;
        require(msg.value >= registrationCost, "Price too low.");
        
        if (registeredExpiryMapping[name][sender] < block.timestamp) {
            // register new name
            registeredMapping[name] = sender;
            registeredLockAmountMapping[name][sender] = msg.value;
            registeredExpiryMapping[name][sender] = block.timestamp + registeredExpiryMinutes;
            emit Registered(name, sender, registeredExpiryMapping[name][sender]);                    
        } else if (registeredExpiryMapping[name][sender] >= block.timestamp) {
            // name has not expired. do nothing.
            revert("Your registration is still active");
        }
    }

    /**
        call this function to get your balance unlocked if a name is expired
    */
    function refundExpired(string memory name) public {
        address sender = msg.sender;
        require(
            registeredMapping[name] == sender,
            "Name registered to another user"
        );
        require(
            registeredExpiryMapping[name][sender] < block.timestamp,
            "Name not expired"
        );

        uint256 amountLocked = registeredLockAmountMapping[name][sender];
        (bool success, ) = payable(sender).call{value: amountLocked}("");
        require(
            success,
            "Unlock Expired failed: Can not transfer locked amount"
        );
    }

    function isLocked(string memory name) public view returns (bool) {
        return lockMapping[name] != address(0);
    }

    function isRegistered(string memory name) public view returns (bool) {
        return registeredMapping[name] != address(0);
    }

    //========================================================================================
    /**
        these methods exists only for testing purposes. 
        although in the real world, an admin may want to force an expire 
     */
    function forceExpireLock(string memory name, address user) public {
        require(msg.sender == admin, 'Only Admin');
        lockExpiryMapping[name][user] = block.timestamp;
    }

    function forceExpireRegistration(string memory name, address user) public {
        require(msg.sender == admin, 'Only Admin');
        registeredExpiryMapping[name][user] = block.timestamp;
    }    

    //========================================================================================
}

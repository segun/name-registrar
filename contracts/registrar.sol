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

    event Renew(
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

    modifier onlyAdmin(address sender) {
        require(msg.sender == admin, 'Only Admin');
        _;
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

    /**
        // https://forum.openzeppelin.com/t/protecting-against-front-running-and-transaction-reordering/1314

        Basically, a user first announces they want to register a name and this annoucement is locked in before the actual
        call to registration. A Malicious node can see the announcement and make it before the user,
        We can then employ another method to prevent front-running. 
            
        We can safely calculate the gas required before hand, we can check that the gas fees
        sent is not higher than X, where X is what is required to send the transaction successfully.

        Lock will expire after Y minutes
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

    function updateGasRequiredForLock(uint256 _grfl) public onlyAdmin(msg.sender) {                
        gasRequiredForLock = _grfl;
    }

    // gets the price of registring a name
    function calculatePrice(string memory name) public pure returns (uint256) {
        return bytes(name).length; // in wei
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
            // refund any previous locked amount
            uint256 previousLockAmount = registeredLockAmountMapping[name][sender];
            // register new name
            registeredMapping[name] = sender;
            registeredLockAmountMapping[name][sender] = msg.value;
            registeredExpiryMapping[name][sender] = block.timestamp + registeredExpiryMinutes;

            if(previousLockAmount > 0) {
                (bool success, ) = payable(sender).call{value: previousLockAmount}("");
                require(
                    success,
                    "Registeration failed: Can not transfer locked amount"
                );                
            }
            
            emit Registered(name, sender, registeredExpiryMapping[name][sender]);                    
        } else if (registeredExpiryMapping[name][sender] >= block.timestamp) {
            // name has not expired. do nothing.
            revert("Your registration is still active");
        }
    }

    function renewRegistration(string memory name) public {        
        address sender = msg.sender;

        require(registeredMapping[name] == sender, 'Name is not registered to you');
        if (registeredExpiryMapping[name][sender] < block.timestamp) {
            registeredExpiryMapping[name][sender] = block.timestamp + registeredExpiryMinutes;
            emit Renew(name, sender, registeredExpiryMapping[name][sender]);                    
        } else {
            revert("Name registration has not expired");
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
    function forceExpireLock(string memory name, address user) public onlyAdmin(msg.sender) {        
        lockExpiryMapping[name][user] = block.timestamp;
    }

    function forceExpireRegistration(string memory name, address user) public onlyAdmin(msg.sender) {        
        registeredExpiryMapping[name][user] = block.timestamp;
    }    

    //========================================================================================
}

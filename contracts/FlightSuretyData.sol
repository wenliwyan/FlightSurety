pragma solidity ^0.4.25;

import "../node_modules/openzeppelin-solidity/contracts/math/SafeMath.sol";

contract FlightSuretyData {
    using SafeMath for uint256;

    /********************************************************************************************/
    /*                                       DATA VARIABLES                                     */
    /********************************************************************************************/

    address private contractOwner;                                      // Account used to deploy contract
    bool private operational = true;                                    // Blocks all state changes throughout the contract if false

    uint256 constant registrationAnte = 1e19;
    uint256 constant insuranceLimit = 1e18;

    mapping(address => bool) authorizedContracts;

    struct AirlineProfile {
        bool isRegistered;
        bool isFunded;
    }
    mapping(address => AirlineProfile) private airlineProfiles;
    mapping(address => address[]) private registrationApprovals;
    uint8 numRegisteredAirlines = 0;

    struct FlightPassengerProfile {
        bool isPassenger;
        uint256 insurance;
    }
    mapping(address => mapping(bytes32 => FlightPassengerProfile)) private passengers;
    mapping(bytes32 => address[]) private insuredPassengers;
    mapping(address => uint256) private credits;

    /********************************************************************************************/
    /*                                       EVENT DEFINITIONS                                  */
    /********************************************************************************************/


    /**
    * @dev Constructor
    *      The deploying account becomes contractOwner
    */
    constructor(address firstAirline) public
    {
        contractOwner = msg.sender;

        // register first airline when contract is deployed
        airlineProfiles[firstAirline] = AirlineProfile({isRegistered: true, isFunded: false});
        numRegisteredAirlines = 1;
    }

    /********************************************************************************************/
    /*                                       FUNCTION MODIFIERS                                 */
    /********************************************************************************************/

    // Modifiers help avoid duplication of code. They are typically used to validate something
    // before a function is allowed to be executed.

    /**
    * @dev Modifier that requires the "operational" boolean variable to be "true"
    *      This is used on all state changing functions to pause the contract in 
    *      the event there is an issue that needs to be fixed
    */
    modifier requireIsOperational() 
    {
        require(operational, "Contract is currently not operational");
        _;  // All modifiers require an "_" which indicates where the function body will be added
    }

    /**
    * @dev Modifier that requires the "ContractOwner" account to be the function caller
    */
    modifier requireContractOwner()
    {
        require(msg.sender == contractOwner, "Caller is not contract owner");
        _;
    }

    /**
    * @dev Modifier that requires authorized App Contract to be the function caller
    */
    modifier requireAuthorizedContracts()
    {
        require(authorizedContracts[msg.sender], "Caller is not authorized to call this function");
        _;
    }

    // /**
    // * @dev Modifier that requires passenger of the corresponding flight to be the function caller
    // */
    // modifier requireFlightPassenger(address airline, string memory flight, uint256 timestamp)
    // {
    //     bytes32 flightKey = getFlightKey(airline, flight, timestamp);
    //     require(passengers[msg.sender][flightKey].isPassenger, "Caller is not passenger of this flight");
    //     _;
    // }

    /********************************************************************************************/
    /*                                       UTILITY FUNCTIONS                                  */
    /********************************************************************************************/

    /**
    * @dev Get operating status of contract
    *
    * @return A bool that is the current operating status
    */      
    function isOperational() 
                            public 
                            view 
                            returns(bool) 
    {
        return operational;
    }


    /**
    * @dev Sets contract operations on/off
    *
    * When operational mode is disabled, all write transactions except for this one will fail
    */    
    function setOperatingStatus
                            (
                                bool mode
                            ) 
                            external
                            requireContractOwner 
    {
        operational = mode;
    }

    function authorizeCaller(address appContract) external requireIsOperational requireContractOwner {
        authorizedContracts[appContract] = true;
    }

    function deauthorizeCaller(address appContract) external requireIsOperational requireContractOwner {
        delete authorizedContracts[appContract];
    }

    function setTestingMode() external view requireIsOperational {}

    function isRegisteredAirline(address airline) public view returns (bool) {
        return airlineProfiles[airline].isRegistered;
    }

    function isFundedAirline(address airline) public view returns (bool) {
        return airlineProfiles[airline].isFunded;
    }

    function getNumRegisteredAirlines() public view returns (uint8) {
        return numRegisteredAirlines;
    }

    function getInsuranceAmount(address passenger, address airline, string memory flight, uint256 timestamp) public view returns (uint256) {
        bytes32 flightKey = getFlightKey(airline, flight, timestamp);
        return passengers[passenger][flightKey].insurance;
    }

    /********************************************************************************************/
    /*                                     SMART CONTRACT FUNCTIONS                             */
    /********************************************************************************************/

   /**
    * @dev Add an airline to the registration queue
    *      Can only be called from FlightSuretyApp contract
    *
    */   
    function registerAirline(address airline) external requireIsOperational requireAuthorizedContracts returns (bool success, uint votes) {
        require(airlineProfiles[tx.origin].isRegistered, "Caller is not a registered airline");
        require(airlineProfiles[tx.origin].isFunded, "Caller is not funded");
        require(!airlineProfiles[airline].isRegistered, "Airline is already registered");

        if (numRegisteredAirlines < 4) {
            airlineProfiles[airline] = AirlineProfile({isRegistered: true, isFunded: false});
            numRegisteredAirlines += 1;
            success = true;
            votes = 1;
        } else {
            bool isDuplicate = false;
            for (uint i=0; i<registrationApprovals[airline].length; i++) {
                if (registrationApprovals[airline][i] == tx.origin) {
                    isDuplicate = true;
                    break;
                }
            }
            require(!isDuplicate, "Caller has already called this function");

            registrationApprovals[airline].push(tx.origin);
            votes = registrationApprovals[airline].length;

            if (registrationApprovals[airline].length * 2 >= numRegisteredAirlines) {
                airlineProfiles[airline] = AirlineProfile({isRegistered: true, isFunded: false});
                numRegisteredAirlines += 1;
                registrationApprovals[airline] = new address[](0);
                success = true;
            }
        }
    }

   /**
    * @dev Buy insurance for a flight
    *
    */   
    function buy
                            (
                                address airline,
                                string flight,
                                uint256 timestamp
                            )
                            external
                            requireIsOperational
                            payable
    {
        require(msg.value > 0, "Insurance not provided");

        address passenger = msg.sender;
        bytes32 flightKey = getFlightKey(airline, flight, timestamp);
        uint256 currentInsurance = passengers[passenger][flightKey].insurance;
        require(currentInsurance + msg.value <= insuranceLimit, "Total insurance value exceeds limit");

        if (currentInsurance == 0) {
            insuredPassengers[flightKey].push(passenger);
        }
        passengers[passenger][flightKey].insurance = currentInsurance.add(msg.value);
    }

    /**
     *  @dev Credits payouts to insurees
    */
    function creditInsurees
                                (
                                    address airline,
                                    string flight,
                                    uint256 timestamp,
                                    uint8 multiplier,
                                    uint8 divider
                                )
                                external
                                requireIsOperational
                                requireAuthorizedContracts
    {
        bytes32 flightKey = getFlightKey(airline, flight, timestamp);
        for (uint i=0; i<insuredPassengers[flightKey].length; i++) {
            address passenger = insuredPassengers[flightKey][i];
            credits[passenger] = passengers[passenger][flightKey].insurance.mul(multiplier).div(divider);
        }
    }
    

    /**
     *  @dev Transfers eligible payout funds to insuree
     *
    */
    function pay
                            (
                            )
                            external
                            requireIsOperational
    {
        require(credits[msg.sender] > 0, "No available credits");
        uint256 amount = credits[msg.sender];
        credits[msg.sender] = 0;
        msg.sender.transfer(amount);
    }

   /**
    * @dev Initial funding for the insurance. Unless there are too many delayed flights
    *      resulting in insurance payouts, the contract should be self-sustaining
    *
    */   
    function fund
                            (
                            )
                            public
                            requireIsOperational
                            payable
    {
        require(isRegisteredAirline(msg.sender), "Only registered airlines can fund");
        require(!airlineProfiles[msg.sender].isFunded, "Caller has already funded");
        require(msg.value >= registrationAnte, "Not enough fund");
        if (msg.value > registrationAnte) {
            msg.sender.transfer(msg.value - registrationAnte);
        }
        airlineProfiles[msg.sender].isFunded = true;
    }

    function getFlightKey
                        (
                            address airline,
                            string memory flight,
                            uint256 timestamp
                        )
                        pure
                        internal
                        returns(bytes32)
    {
        return keccak256(abi.encodePacked(airline, flight, timestamp));
    }

    /**
    * @dev Fallback function for funding smart contract.
    *
    */
    function()
                            external
                            requireIsOperational
                            payable
    {
        fund();
    }
}


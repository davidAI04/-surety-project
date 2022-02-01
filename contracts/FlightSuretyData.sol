// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;


import "../node_modules/@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract FlightSuretyData is ReentrancyGuard{

    /********************************************************************************************/
    /*                                       DATA VARIABLES                                     */
    /********************************************************************************************/

    address private contractOwner;                                      // Account used to deploy contract
    bool private operational = true;                                    // Blocks all state changes throughout the contract if false
    address[] contractActiveAirlines; // An airline is active when their state is accepted and is already funded
    mapping(address => Airline) private airlines; //mapping for all airlines
    mapping(address => mapping(address => bool)) private voteTracker; //Allow track an airline votes to accept another airline
    mapping(bytes32 => Flight) private flights; //Flights registration
    mapping(address => Surety[]) private insurees; //create a One-to-Many relationship between passengers and their surety
    
    struct Airline {
        bool accepted; //In case of the airline should be voted, once reached the minimum votes accepted will change to true
        uint256 votes; // Votes counter
        bool funded; //the airline can be accepted 
        string code;   //also works with a airline identifier
    }

    struct Flight {
        bool isRegistered; //If the flight is already registered
        uint8 statusCode; //The flight status code 
        string flightIdentifier; //The fligth identifier
        uint256 updatedTimestamp;        
        address airline;//Airline address
        address[] insurees; //create a One-to-Many relationship with ensured passengers
        mapping(address => bool) insureesCheck; //ensurees validation. check if a passenger is ensured
    }

    struct Surety {
      address payable passenger; //ensured person address
      bytes32 fligthKey; //fligth to be ensured
    }

    /********************************************************************************************/
    /*                                       EVENT DEFINITIONS                                  */
    /********************************************************************************************/


    /**
    * @dev Constructor
    *      The deploying account becomes contractOwner
    */
    constructor
                                (
                                ) 
                                
    {
        contractOwner = msg.sender;
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
    * @dev Modifier that requires the an airline only can vote once for the same airline
    */
    modifier isADoubleVote(address newAirlineAddress) {
      require(voteTracker[msg.sender][newAirlineAddress] == false, "You can't vote twice for the same airline");
      _;
    }

    /**
    * @dev The airline should fund a value equal or grater than 10 ether to participate in the contract
    */
    modifier requireAmount() {
      require(msg.value >= 10 ether, "You dont sent the right ETH value");
      _;
    }

    /**
    * @dev check if a airline NOT EXIST in the airlines mapping
    */
    modifier AirlineNOTExist(address airlineAddress, string memory code) {
      require (getStringLength(code) != 0, "Empty airline code not allowed");
      require(keccak256(abi.encode(airlines[airlineAddress].code)) != keccak256(abi.encode(code)), "The airline already exist");
      _;
    }

    /**
    * @dev check if a airline EXIST in the airlines mapping
    */
    modifier AirlineExist(address airlineAddress, string memory code) {
      require (getStringLength(code) != 0, "Empty airline code not allowed");
      require(keccak256(abi.encode(airlines[airlineAddress].code)) == keccak256(abi.encode(code)), "The airline not exist");
      _;
    }


    /**
    * @dev Modifier that requires the multi party consensus is already enable
    */
    modifier isMultiPartyAccepted() {
      require(contractActiveAirlines.length >= 4, "We're not receiving votes yet ");
      _;
    }

    /**
    * @dev Modifier that requires the airline is still in queue
    */
    modifier isAnAirlineInQueue(address newAirline) {
      require(airlines[newAirline].accepted == false, "The airline is still in queue");
      _;
    }

    /**
    * @dev Modifier that requires the airline is accepted and funded to participate in the contract
    */
    modifier isAEnableAirline(address callerAirline) {
      Airline memory airlineReference = airlines[callerAirline];
      require(airlineReference.accepted != false && airlineReference.funded != false , "You can't participate on this contract");
      _;
    }

    /**
    * @dev Modifier that requires the airline is not funded yet
    */
    modifier isNotFundedYet(address callerAirline) {
      require(airlines[callerAirline].funded != false, "This airline is already funded");
      _;
    }

    /**
    * @dev Modifier that requires the fligth is NOT ALREADY registered
    */
    modifier isAFligthNotResgisteredYet(bytes32 fligthKey) {
      require(flights[fligthKey].isRegistered != true, "Fligth already registered");
      _;
    }

    /**
    * @dev Modifier that requires the fligth is ALREADY registered
    */
    modifier isAlreadyResgisteredFligth(bytes32 fligthKey) {
      require(flights[fligthKey].isRegistered != true, "Fligth is not registered");
      _;
    }

    modifier isNotAFlightInProgress(bytes32 fligthKey) {
      require(flights[fligthKey].statusCode == 0, "Fligth is already in progress");
      _;
    }

    modifier isNotInsureedYet(bytes32 fligthKey) {
      require(flights[fligthKey].insureesCheck[msg.sender] == false, "Passenger already ensureed");
      _;
    }
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
    
    /**
    * @dev get a string and return its length
    */
    function getStringLength (string memory referenceString) internal pure returns (uint) {
      return bytes(referenceString).length;
    }

    /********************************************************************************************/
    /*                                     SMART CONTRACT FUNCTIONS                             */
    /********************************************************************************************/

   /**
    * @dev Add an airline to the registration queue
    *  Can only be called from FlightSuretyApp contract
    */   
    function registerAirline (
      address callerAirline,
      address newAirlineAddress,
      string memory code,
      bool queue //If the airline must to receive votes from another airlines to be accepted 
    ) external 
      requireIsOperational 
      isAEnableAirline(callerAirline) 
      AirlineNOTExist(newAirlineAddress, code)
      nonReentrant {
      airlines[newAirlineAddress].code = code;
      airlines[newAirlineAddress].funded = false;
      airlines[newAirlineAddress].accepted = queue;
      airlines[newAirlineAddress].votes = 0;
    }

    /**
    * @dev register the vote for an airline in the multiparty concensus
    */ 

     function registerVote (
      address callerAirline,
      address newAirlineAddress,
      string memory code,
      uint votesQuantityToBeAccepted
    ) external 
      requireIsOperational
      isMultiPartyAccepted
      isAEnableAirline(callerAirline)
      AirlineExist(newAirlineAddress, code)
      isADoubleVote(newAirlineAddress)
      isAnAirlineInQueue(newAirlineAddress)
      nonReentrant {
      voteTracker[msg.sender][newAirlineAddress] = true;
      airlines[newAirlineAddress].votes += 1;
      //Check if whit the current amount of votes, the airline can be already accepted
      if(airlines[newAirlineAddress].votes >= votesQuantityToBeAccepted) {
        airlines[newAirlineAddress].accepted = true;
        if(airlines[newAirlineAddress].funded) {
          contractActiveAirlines.push(callerAirline);
        }
      }
    }

    /**
    * @dev Initial funding for the insurance. Unless there are too many delayed flights
    *      resulting in insurance payouts, the contract should be self-sustaining
    */   
    function fundAirlineMembership (string memory code) 
      public payable 
      requireAmount 
      AirlineExist(msg.sender, code)
      isNotFundedYet(msg.sender)
      nonReentrant {
        _fundAirlineMembership(msg.sender);
    }

    /**
    * @dev Update the airline funded state and active airlines array
    */
    function _fundAirlineMembership (address fundedAirline) private nonReentrant {
      airlines[fundedAirline].funded = true;
      if (airlines[fundedAirline].funded && airlines[fundedAirline].accepted) {
        contractActiveAirlines.push(fundedAirline);
      }
    }


    /**
    * @dev Register a future flight for insuring.
    */
    function registerFlight(
        uint8 statusCode,
        uint256 timestamp,
        address airline,
        string memory flightIdentifier,
        bytes32 fligthKey
      )
      external 
      requireIsOperational
      isAEnableAirline(airline)
      isAFligthNotResgisteredYet(fligthKey)
      nonReentrant
    { 
      Flight storage flightReference = flights[fligthKey];
      flightReference.isRegistered = true;
      flightReference.statusCode = statusCode;
      flightReference.flightIdentifier = flightIdentifier;
      flightReference.updatedTimestamp = timestamp;
      flightReference.airline = airline;
    }

   /**
    * @dev Buy insurance for a flight
    *
    */   
    function buy(
      address passenger,
      bytes32 fligthKey
    )
      external
      payable
      requireIsOperational
      isAlreadyResgisteredFligth(fligthKey)
      isNotAFlightInProgress(fligthKey)
      isNotInsureedYet(fligthKey)
      nonReentrant
    {

      Surety memory suretyReference;
      suretyReference.passenger = payable(passenger);
      suretyReference.fligthKey = fligthKey;

      insurees[msg.sender].push(suretyReference);
      flights[fligthKey].insureesCheck[msg.sender] = true;
      flights[fligthKey].insurees.push(msg.sender);
      
    }

    /**
     *  @dev Credits payouts to insurees
    */
    function creditInsurees
                                (
                                )
                                external
                                pure
    {
    }
    

    /**
     *  @dev Transfers eligible payout funds to insuree
     *
    */
    function pay
                            (
                            )
                            external
                            pure
    {
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


}


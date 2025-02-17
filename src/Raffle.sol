// SPDX-License-Identifier: MIT
/*
Layout contract elements in the following order:

Pragma statements
Import statements
Interfaces
Libraries
Contracts

Inside each contract, library or interface, use the following order:

Type declarations
State variables
Events
Errors
Modifiers
Functions
*/

/**
 * @title Raffle contract
 * @author Miu Vlad-Alexandru
 * @notice Creating raffle
 */
pragma solidity 0.8.19;

import {VRFConsumerBaseV2Plus} from
    "../lib/chainlink-brownie-contracts/contracts/src/v0.8/vrf/dev/VRFConsumerBaseV2Plus.sol";
import {VRFV2PlusClient} from
    "../lib/chainlink-brownie-contracts/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";

contract Raffle is VRFConsumerBaseV2Plus {
    /* Type declarations */
    enum RaffleState {
        OPEN, //0
        CALCULATING //1

    }

    /* State variables */
    uint16 private constant REQUEST_CONFIRMATIONS = 3;
    uint32 private constant NUM_WORDS = 1;
    uint256 private immutable i_entranceFee;
    uint256 private immutable i_interval;
    uint256 private immutable i_subscriptionId;
    bytes32 private immutable i_keyHash;
    uint32 private immutable i_callbackGasLimit;
    uint256 private s_lastTimeStamp;
    address payable[] private s_players;
    address private s_recentWinner;
    RaffleState private s_raffleState;

    /* Events */
    event RaffleEntered(address indexed player);
    event WinnerPicked(address indexed winner);
    event RequestedRaffleWinner(uint256 indexed requestId);

    /* Errors */
    error Raffle__NotEnoughEth();
    error Raffle__TransferFailed();
    error Raffle__RaffleNotOpen();
    error Raffle__UpKeepNotNeeded(uint256 balance, uint256 playersLength, RaffleState raffleState);

    constructor(
        uint256 entranceFee,
        uint256 interval,
        address vrfCoordinator,
        bytes32 gasLane,
        uint256 subscriptionId,
        uint32 callbackGasLimit
    ) VRFConsumerBaseV2Plus(vrfCoordinator) {
        i_entranceFee = entranceFee;
        i_interval = interval;
        i_keyHash = gasLane;
        i_subscriptionId = subscriptionId;
        i_callbackGasLimit = callbackGasLimit;

        s_raffleState = RaffleState.OPEN;
        s_lastTimeStamp = block.timestamp;
    }

    function enterRaffle() public payable {
        if (s_raffleState != RaffleState.OPEN) {
            revert Raffle__RaffleNotOpen();
        }

        if (msg.value < i_entranceFee) {
            revert Raffle__NotEnoughEth();
        }
        s_players.push(payable(msg.sender));
        emit RaffleEntered(msg.sender);
    }

    /**
     * @dev This is the function that chainlink calls
     * @param - ignored
     * @return upkeepNeeded - true if its time to restart the lottery
     * @return - ginored
     */
    function checkUpKeep(bytes memory) public view returns (bool upkeepNeeded, bytes memory /* performData */ ) {
        bool timeHasPassed = ((block.timestamp - s_lastTimeStamp) >= i_interval);
        bool isOpen = s_raffleState == RaffleState.OPEN;
        bool hasBalance = address(this).balance > 0;
        bool hasPlayers = s_players.length > 0;
        upkeepNeeded = timeHasPassed && isOpen && hasBalance && hasPlayers;
        return (upkeepNeeded, "");
    }

    function performUpkeep(bytes calldata) external {
        // Checks
        (bool upKeepNeeded,) = checkUpKeep("");
        if (!upKeepNeeded) {
            revert Raffle__UpKeepNotNeeded(address(this).balance, s_players.length, s_raffleState);
        }

        // Effects (internal contract state)
        s_raffleState = RaffleState.CALCULATING;
        uint256 requestId = s_vrfCoordinator.requestRandomWords(
            VRFV2PlusClient.RandomWordsRequest({
                keyHash: i_keyHash, // gas price somehow from the documentation
                subId: i_subscriptionId,
                requestConfirmations: REQUEST_CONFIRMATIONS,
                callbackGasLimit: i_callbackGasLimit,
                numWords: NUM_WORDS,
                extraArgs: VRFV2PlusClient._argsToBytes(VRFV2PlusClient.ExtraArgsV1({nativePayment: false}))
            })
        );
        emit RequestedRaffleWinner(requestId);
    }

    // CEI: Checks, Effects, Interactcions gas efficient
    function fulfillRandomWords(uint256 requstId, uint256[] calldata randomWords) internal override {
        // Checks

        // Effects (internal contract state)
        uint256 indexOfWinner = randomWords[0] % s_players.length;
        address payable recentWinner = s_players[indexOfWinner];
        s_recentWinner = recentWinner;
        s_raffleState = RaffleState.OPEN;
        s_players = new address payable[](0);
        s_lastTimeStamp = block.timestamp;
        emit WinnerPicked(s_recentWinner);

        //Interactions (external contract interactions)
        (bool success,) = recentWinner.call{value: address(this).balance}("");
        if (!success) {
            revert Raffle__TransferFailed();
        }
    }

    // Getter functions

    function getEntrenceFee() external view returns (uint256) {
        return i_entranceFee;
    }

    function getRaffleState() public view returns (RaffleState) {
        return s_raffleState;
    }

    function getPlayers() public view returns (address payable[] memory) {
        return s_players;
    }

    function getLastTimestamp() public view returns (uint256) {
        return s_lastTimeStamp;
    }

    function getRecentWinner() public view returns (address) {
        return s_recentWinner;
    }
}

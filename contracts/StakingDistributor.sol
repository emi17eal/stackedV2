// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8;

import './libraries/LowGasSafeMath.sol';
import '@openzeppelin/contracts/utils/Address.sol';
import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';

interface IERC20Mintable {
  function mint( uint256 amount_ ) external;

  function mint( address account_, uint256 ammount_ ) external;
}

interface ISTACKERC20 is IERC20Mintable, IERC20 {
    function burnFrom(address account_, uint256 amount_) external;
}

contract Distributor is Ownable {
    using LowGasSafeMath for uint;
    using LowGasSafeMath for uint32;
    

    /* ====== VARIABLES ====== */

    ISTACKERC20 public immutable STACK;

    uint32 public immutable epochLength;
    uint32 public nextEpochTime;
    
    mapping ( address => bool) public isRewardManager;

    event RewardsMinted( address indexed caller, address indexed recipient, uint amount );
    event LogDistribute(address indexed recipient, uint amount);
    event LogAdjust(uint initialRate, uint currentRate, uint targetRate);
    event LogAddRecipient(address indexed recipient, uint rate);
    event LogRemoveRecipient(address indexed recipient);
    
    /* ====== STRUCTS ====== */
        
    struct Info {
        uint rate; // in ten-thousandths ( 5000 = 0.5% )
        address recipient;
    }

    Info[] public info;
    
    struct Adjust {
        bool add;
        uint rate;
        uint target;
    }
    
    mapping ( uint => Adjust ) public adjustments;

    
    
    /* ====== CONSTRUCTOR ====== */

    constructor( address _stack, uint32 _epochLength, uint32 _nextEpochTime ) {        
        require( _stack != address(0) );
        STACK = ISTACKERC20(_stack);
        epochLength = _epochLength;
        nextEpochTime = _nextEpochTime;
        isRewardManager[msg.sender] = true;
    }
    
    /* ====== PUBLIC FUNCTIONS ====== */
    
    /**
        @notice send epoch reward to staking contract
     */
    function distribute() external returns ( bool ) {
        if ( nextEpochTime <= uint32(block.timestamp) ) {
            nextEpochTime = nextEpochTime.add32( epochLength ); // set next epoch time
            
            // distribute rewards to each recipient
            for ( uint i = 0; i < info.length; i++ ) {
                if ( info[ i ].rate > 0 ) {
                    mintRewards( // mint and send from treasury
                        info[ i ].recipient, 
                        nextRewardAt( info[ i ].rate ) 
                    );
                    adjust( i ); // check for adjustment
                }
                emit LogDistribute(info[ i ].recipient, nextRewardAt( info[ i ].rate ));
            }
            return true;
        } else { 
            return false; 
        }
    }

    /**
        @notice send epoch reward to staking contract
     */
    function mintRewards( address _recipient, uint _amount ) public {
        require( isRewardManager[ msg.sender ], "Not approved" );
        STACK.mint( _recipient, _amount );
        emit RewardsMinted( msg.sender, _recipient, _amount );
    } 
    

    /* ====== INTERNAL FUNCTIONS ====== */

    /**
        @notice increment reward rate for collector
     */
    function adjust( uint _index ) internal {
        Adjust memory adjustment = adjustments[ _index ];
        if ( adjustment.rate != 0 ) {
            uint initial = info[ _index ].rate;
            uint rate = initial;
            if ( adjustment.add ) { // if rate should increase
                rate = rate.add( adjustment.rate ); // raise rate
                if ( rate >= adjustment.target ) { // if target met
                    rate = adjustment.target;
                    delete adjustments[ _index ];
                }
            } else { // if rate should decrease
                rate = rate.sub( adjustment.rate ); // lower rate
                if ( rate <= adjustment.target ) { // if target met
                    rate = adjustment.target;
                    delete adjustments[ _index ];
                }
            }
            info[ _index ].rate = rate;
            emit LogAdjust(initial, rate, adjustment.target);
        }
    }
    
    
    /* ====== VIEW FUNCTIONS ====== */

    /**
        @notice view function for next reward at given rate
        @param _rate uint
        @return uint
     */
    function nextRewardAt( uint _rate ) public view returns ( uint ) {
        return STACK.totalSupply().mul( _rate ).div( 1000000 );
    }

    /**
        @notice view function for next reward for specified address
        @param _recipient address
        @return uint
     */
    function nextRewardFor( address _recipient ) external view returns ( uint ) {
        uint reward;
        for ( uint i = 0; i < info.length; i++ ) {
            if ( info[ i ].recipient == _recipient ) {
                reward = nextRewardAt( info[ i ].rate );
            }
        }
        return reward;
    }
    
    
    
    /* ====== POLICY FUNCTIONS ====== */

    function editRewardManager (address _newRewardManager, bool _bool) external onlyOwner {
        isRewardManager[_newRewardManager] = _bool;
    }

    /**
        @notice adds recipient for distributions
        @param _recipient address
        @param _rewardRate uint
     */
    function addRecipient( address _recipient, uint _rewardRate ) external onlyOwner {
        require( _recipient != address(0), "IA" );
        require(info.length <= 4, "limit recipients max to 5");
        info.push( Info({
            recipient: _recipient,
            rate: _rewardRate
        }));
        emit LogAddRecipient(_recipient, _rewardRate);
    }

    /**
        @notice removes recipient for distributions
        @param _index uint
        @param _recipient address
     */
    function removeRecipient( uint _index, address _recipient ) external onlyOwner {
        require( _recipient == info[ _index ].recipient, "NA" );
        info[_index] = info[info.length-1];
        adjustments[_index] = adjustments[ info.length-1 ];
        info.pop();
        delete adjustments[ info.length-1 ];
        emit LogRemoveRecipient(_recipient);
    }

    /**
        @notice set adjustment info for a collector's reward rate
        @param _index uint
        @param _add bool
        @param _rate uint
        @param _target uint
     */
    function setAdjustment( uint _index, bool _add, uint _rate, uint _target ) external onlyOwner {
        adjustments[ _index ] = Adjust({
            add: _add,
            rate: _rate,
            target: _target
        });
    }
}
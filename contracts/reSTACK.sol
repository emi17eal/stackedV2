//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "hardhat/console.sol";
import "./types/ERC20NFTOwned.sol";
import '@openzeppelin/contracts/access/Ownable.sol';

interface INFT is IERC721 {
    function ownerOf(uint256 tokenId) external view override returns (address);
}

interface IStaking {
    function supplyInWarmup() external view returns (uint supply);
}

contract RebaseStack is ERC20NFTOwned, Ownable {

    modifier onlyStakingContract() {
        require( msg.sender == address(staking), "OSC" );
        _;
    }

    uint32 public stakingContractId;
    address public initializer;
    IStaking public staking;

    event LogSupply(uint256 indexed epoch, uint256 timestamp, uint256 totalSupply );
    event LogRebase( uint256 indexed epoch, uint256 rebase, uint256 index );
    event LogStakingContractUpdated( address stakingContract );
    event LogSetIndex(uint256 indexed index );

    struct Rebase {
        uint epoch;
        uint rebase; // 18 decimals
        uint totalStakedBefore;
        uint totalStakedAfter;
        uint amountRebased;
        uint index;
        uint32 timeOccured;
    }
    Rebase[] public rebases;

    uint public INDEX;

    uint256 private constant MAX_UINT256 = ~uint256(0);
    uint256 private constant INITIAL_FRAGMENTS_SUPPLY = 5000000 * 10**9;

    // TOTAL_GONS is a multiple of INITIAL_FRAGMENTS_SUPPLY so that _gonsPerFragment is an integer.
    // Use the highest value that fits in a uint256 for max granularity.
    uint256 private constant TOTAL_GONS = MAX_UINT256 - (MAX_UINT256 % INITIAL_FRAGMENTS_SUPPLY);

    // MAX_SUPPLY = maximum integer < (sqrt(4*TOTAL_GONS + 1) - 1) / 2
    uint256 private constant MAX_SUPPLY = ~uint128(0);  // (2^128) - 1

    uint256 private _gonsPerFragment;
    mapping(uint256 => uint256) private _gonBalances;  // tokenIds

    mapping ( uint256 => mapping ( uint256 => uint256 ) ) private _allowedValue;   // tokenIds

    constructor(address _nftContract) ERC20NFTOwned("RebaseStack", "reSTACK", _nftContract) {
        initializer = msg.sender;
        _totalSupply = INITIAL_FRAGMENTS_SUPPLY;
        _gonsPerFragment = TOTAL_GONS/_totalSupply;
    }

    function initialize( uint32 _stakingContractId, address stakingContract_) external returns ( bool ) {
        require( msg.sender == initializer, "NA" );
        require( stakingContract_ != address(0), "IA" );
        stakingContractId = _stakingContractId;
        staking = IStaking(stakingContract_);
        _gonBalances[ stakingContractId ] = TOTAL_GONS;

        emit Mint( stakingContractId, _totalSupply );
        emit LogStakingContractUpdated( stakingContract_ );
        
        initializer = address(0);
        return true;
    }

    function setIndex( uint _INDEX ) external onlyOwner() {
        require( INDEX == 0, "INZ");
        INDEX = gonsForBalance( _INDEX );
        emit LogSetIndex(INDEX);
    }

    /**
        @notice increases MEMOries supply to increase staking balances relative to profit_
        @param profit_ uint256
        @return uint256
     */
    function rebase( uint256 profit_, uint epoch_ ) public onlyStakingContract() returns ( uint256 ) {
        uint256 rebaseAmount;
        uint256 circulatingSupply_ = circulatingSupply();

        if ( profit_ == 0 ) {
            emit LogSupply( epoch_, block.timestamp, _totalSupply );
            emit LogRebase( epoch_, 0, index() );
            return _totalSupply;
        } else if ( circulatingSupply_ > 0 ){
            rebaseAmount = (profit_* _totalSupply)/( circulatingSupply_ );
        } else {
            rebaseAmount = profit_;
        }

        _totalSupply = _totalSupply + rebaseAmount;

        if ( _totalSupply > MAX_SUPPLY ) {
            _totalSupply = MAX_SUPPLY;
        }

        _gonsPerFragment = TOTAL_GONS/_totalSupply;

        _storeRebase( circulatingSupply_, profit_, epoch_ );

        return _totalSupply;
    }

    /**
        @notice emits event with data about rebase
        @param previousCirculating_ uint
        @param profit_ uint
        @param epoch_ uint
        @return bool
     */
    function _storeRebase( uint previousCirculating_, uint profit_, uint epoch_ ) internal returns ( bool ) {
        uint rebasePercent = (profit_*( 1e18 ))/previousCirculating_;

        rebases.push( Rebase ( {
            epoch: epoch_,
            rebase: rebasePercent, // 18 decimals
            totalStakedBefore: previousCirculating_,
            totalStakedAfter: circulatingSupply(),
            amountRebased: profit_,
            index: index(),
            timeOccured: uint32(block.timestamp)
        }));
        
        emit LogSupply( epoch_, block.timestamp, _totalSupply );
        emit LogRebase( epoch_, rebasePercent, index() );

        return true;
    }

    function balanceOf( uint32 who ) public view override returns ( uint256 ) {
        return _gonBalances[ who ]/( _gonsPerFragment );
    }

    function gonsForBalance( uint amount ) public view returns ( uint ) {
        return amount*( _gonsPerFragment );
    }

    function balanceForGons( uint gons ) public view returns ( uint ) {
        return gons/( _gonsPerFragment );
    }

    // Staking contract holds excess MEMOries
    function circulatingSupply() public view returns ( uint ) {
        return _totalSupply - balanceOf( stakingContractId ) + staking.supplyInWarmup();
    }

    function index() public view returns ( uint ) {
        return balanceForGons( INDEX );
    }

    function transfer( uint32 fromId, uint32 toId, uint256 value ) public override returns (bool) {
        require (nftContract.ownerOf(fromId) == msg.sender, "You do not own this tokenId" );
        uint256 gonValue = value * ( _gonsPerFragment );
        _gonBalances[ fromId ] = _gonBalances[ fromId ] - gonValue;
        _gonBalances[ toId ] = _gonBalances[ toId ] + gonValue;
        emit Transfer( fromId, toId, value );
        return true;
    }

    function allowance( uint32 ownerId, uint32 spenderId ) public view override returns ( uint256 ) {
        return _allowedValue[ ownerId ][ spenderId ];
    }

    function transferFrom( uint32 fromId, uint32 toId, uint32 spenderId, uint256 value ) public override returns ( bool ) {
        require (nftContract.ownerOf(spenderId) == msg.sender, "You do not own this tokenId" );
       _allowedValue[ fromId ][ spenderId ] -= value;
       emit Approval( fromId, spenderId,  _allowedValue[ fromId ][ spenderId ] );

        uint256 gonValue = gonsForBalance( value );
        _gonBalances[ fromId ] -= gonValue;
        _gonBalances[ toId ] +=  gonValue;
        emit Transfer( fromId, toId, value );

        return true;
    }

    function approve( uint32 ownerId, uint32 spenderId, uint256 value ) public override returns (bool) {
        require (nftContract.ownerOf(ownerId) == msg.sender, "You do not own this tokenId" );
         _allowedValue[ ownerId ][ spenderId ] = value;
         emit Approval( ownerId, spenderId, value );
         return true;
    }

    // What gets called in a permit
    function _approve( uint32 ownerId, uint32 spenderId, uint256 value ) internal override virtual {
        _allowedValue[ownerId][spenderId] = value;
        emit Approval( ownerId, spenderId, value );
    }

    function increaseAllowance( uint32 fromId, uint32 spenderId, uint256 addedValue ) public override returns (bool) {
        require (nftContract.ownerOf(fromId) == msg.sender, "You do not own this tokenId" );
        _allowedValue[ fromId ][ spenderId ] += addedValue;
        emit Approval( fromId, spenderId, _allowedValue[ fromId ][ spenderId ] );
        return true;
    }

    function decreaseAllowance( uint32 fromId, uint32 spenderId, uint256 subtractedValue ) public override returns (bool) {
        require (nftContract.ownerOf(fromId) == msg.sender, "You do not own this tokenId" );
        uint256 oldValue = _allowedValue[ fromId ][ spenderId ];
        if (subtractedValue >= oldValue) {
            _allowedValue[ fromId ][ spenderId ] = 0;
        } else {
            _allowedValue[ fromId ][ spenderId ] = oldValue - subtractedValue;
        }
        emit Approval( fromId, spenderId, _allowedValue[ fromId ][ spenderId ] );
        return true;
    }
}

// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8;

import "hardhat/console.sol";
import './libraries/LowGasSafeMath.sol';
import '@openzeppelin/contracts/utils/Address.sol';
import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import './types/IERC20NFTOwned.sol';
import '@openzeppelin/contracts/token/ERC721/IERC721.sol';
import '@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol';

library SafeERC20 {
    using LowGasSafeMath for uint256;
    using Address for address;

    function safeTransfer(IERC20 token, address to, uint256 value) internal {
        _callOptionalReturn(token, abi.encodeWithSelector(token.transfer.selector, to, value));
    }

    function safeTransferFrom(IERC20 token, address from, address to, uint256 value) internal {
        _callOptionalReturn(token, abi.encodeWithSelector(token.transferFrom.selector, from, to, value));
    }

    /**
     * @dev Deprecated. This function has issues similar to the ones found in
     * {IERC20-approve}, and its usage is discouraged.
     *
     * Whenever possible, use {safeIncreaseAllowance} and
     * {safeDecreaseAllowance} instead.
     */
    function safeApprove(IERC20 token, address spender, uint256 value) internal {
        // safeApprove should only be called when setting an initial allowance,
        // or when resetting it to zero. To increase and decrease it, use
        // 'safeIncreaseAllowance' and 'safeDecreaseAllowance'
        // solhint-disable-next-line max-line-length
        require((value == 0) || (token.allowance(address(this), spender) == 0),
            "SafeERC20: approve from non-zero to non-zero allowance"
        );
        _callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, value));
    }

    function safeIncreaseAllowance(IERC20 token, address spender, uint256 value) internal {
        uint256 newAllowance = token.allowance(address(this), spender).add(value);
        _callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, newAllowance));
    }

    function safeDecreaseAllowance(
        IERC20 token, 
        address spender, 
        uint256 value
    ) internal {
        uint256 newAllowance = token.allowance(address(this), spender)
            .sub(value);
        _callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, newAllowance));
    }

    /**
     * @dev Imitates a Solidity high-level call (i.e. a regular function call to a contract), relaxing the requirement
     * on the return value: the return value is optional (but if data is returned, it must not be false).
     * @param token The token targeted by the call.
     * @param data The call data (encoded using abi.encode or one of its variants).
     */
    function _callOptionalReturn(IERC20 token, bytes memory data) private {
        // We need to perform a low level call here, to bypass Solidity's return data size checking mechanism, since
        // we're implementing it ourselves. We use {Address.functionCall} to perform this call, which verifies that
        // the target address contains contract code and also asserts for success in the low-level call.

        bytes memory returndata = address(token).functionCall(data, "SafeERC20: low-level call failed");
        if (returndata.length > 0) { // Return data is optional
            // solhint-disable-next-line max-line-length
            require(abi.decode(returndata, (bool)), "SafeERC20: ERC20 operation did not succeed");
        }
    }
}


interface IreSTACK is IERC20NFTOwned {
    function rebase( uint256 ohmProfit_, uint epoch_) external returns (uint256);

    function circulatingSupply() external view returns (uint256);

    function balanceOf(uint32 id) external view override returns (uint256);

    function gonsForBalance( uint amount ) external view returns ( uint );

    function balanceForGons( uint gons ) external view returns ( uint );
    
    function index() external view returns ( uint );
}

interface IDistributor {
    function distribute() external returns ( bool );
}

interface INFT is IERC721 {
    function getTokenBalances(uint _tokenID, address _address) external view returns(uint balance);

    function addGons(uint32 _tokenID, uint _gons) external;
    
    function removeGons(uint32 _tokenID, uint _gons) external;

    function reStackBalance(uint32 _tokenID) external view returns(uint);

    function gonsBalance(uint32 _tokenID) external view returns(uint);

    function ownerOf(uint256 tokenId) external view override returns (address);
}

contract StackStaking is Ownable, IERC721Receiver {

    using SafeERC20 for IERC20;

    /* ====== VARIABLES ====== */

    IERC20 public immutable STACK;
    IreSTACK public immutable reSTACK;
    IDistributor public distributor;
    INFT public nftContract;

    mapping (address => uint) public stackClaims;


    address public bondContract;

    uint32 public immutable stakingTokenId;
    uint32 public immutable bondTokenId;
    uint public totalBonus;
    uint public warmupPeriod = 1;
    uint private gonsInWarmup;

    event LogStake(uint32 indexed nft, uint256 amount);
    event LogClaim(uint32 indexed nft, uint256 amount);
    event LogForfeit(uint32 indexed nft, uint256 reStackAmount, uint256 StackAmount);
    event LogDepositLock(uint32 indexed nft, bool locked);
    event LogUnstake(uint32 indexed nft, uint256 amount);
    event LogRebase(uint256 distribute);
    event LogSetContract(CONTRACTS contractType, address indexed _contract);
    event LogWarmupPeriod(uint period);
    
    /* ====== STRUCTS ====== */

    struct Epoch {
        uint number;
        uint distribute;
        uint32 length;
        uint32 endTime;
    }

    Epoch public epoch;

    struct Claim {
        uint deposit;
        uint gons;
        uint expiry;
        bool lock;   // prevents malicious delays
    }

    mapping( uint32 => Claim ) public warmupInfo;

    struct Pool {
        address owner;
        uint fee;       // in thousandths i.e. 5000 = 5%
        uint minTime;   // min time before owner can close pool
    }

    mapping (uint32 => Pool) public pools;

    struct Pooler {
        address pooler;
        uint gons;
    }

    mapping (uint32 => Pooler[]) public poolers;

    /* ====== CONSTRUCTOR ====== */

    constructor ( 
        address _stack, 
        address _reSTACK, 
        uint32 _epochLength,
        uint _firstEpochNumber,
        uint32 _firstEpochTime,
        uint32 _stakingTokenId,
        uint32 _bondTokenId
    ) {
        require( _stack != address(0) );
        STACK = IERC20(_stack);
        require( _reSTACK != address(0) );
        reSTACK = IreSTACK(_reSTACK);
        
        stakingTokenId = _stakingTokenId;
        bondTokenId = _bondTokenId;

        epoch = Epoch({
            length: _epochLength,
            number: _firstEpochNumber,
            endTime: _firstEpochTime,
            distribute: 0
        });
    }

    /* ====== PUBLIC FUNCTIONS ====== */

    /**
        @notice stake to enter warmup
        @param _tokenID uint32
        @param _amount uint
        @return bool
     */
    function stake( uint32 _tokenID, uint _amount )
    external returns(bool) 
    {
        require(_amount > 0, 'must deposit more than zero');
        require(nftContract.ownerOf(_tokenID) == msg.sender, 'you do not own this tokenID');
        rebase();

        STACK.safeTransferFrom( msg.sender, address(this), _amount );

        Claim memory info = warmupInfo[ _tokenID ];
        require( !info.lock, "Deposits for account are locked" );

        warmupInfo[ _tokenID ] = Claim ({
            deposit: info.deposit + _amount,
            gons: info.gons + reSTACK.gonsForBalance( _amount ),
            expiry: epoch.number + warmupPeriod,
            lock: false
        });

        gonsInWarmup += reSTACK.gonsForBalance( _amount );
        
        emit LogStake(_tokenID, _amount);
        return true;
    }


    /**
        @notice claim from warmup
        @param _nft uint32    
     */
    function claim( uint32 _nft ) 
    external 
    {
        require(nftContract.ownerOf(_nft) == msg.sender, 'you do not own this NFT');

        Claim memory info = warmupInfo[ _nft ];
        require( epoch.number >= info.expiry && info.expiry != 0, 'Still in warmup' );
        delete warmupInfo[ _nft ];

        uint256 amount = reSTACK.balanceForGons( info.gons );
        gonsInWarmup -= info.gons;

        // transfer restack from staking nft to claimant
        reSTACK.transfer( stakingTokenId, _nft, amount );
        emit LogClaim(_nft, amount);
    }


    /**
        @notice forfeit reSTACK in warmup and retrieve STACK
        @param _nft uint32
     */
    function forfeit( uint32 _nft )
    external 
    {
        require(nftContract.ownerOf( _nft ) == msg.sender, 'you do not own this NFT');
        Claim memory info = warmupInfo[ _nft ];
        delete warmupInfo[ _nft ];
        gonsInWarmup -= info.gons;
        uint reSTACKbalance = reSTACK.balanceForGons( info.gons );
        STACK.safeTransfer( msg.sender, info.deposit);
        emit LogForfeit(_nft, reSTACKbalance, info.deposit);
    }


    /**
        @notice redeem STACK for reSTACK
        @param _nft uint32
        @param _amount uint
        @param _trigger bool
     */
    function unstake( uint32 _nft, uint _amount, bool _trigger )
    external
    {
        require(nftContract.ownerOf(_nft) == msg.sender, 'you do not own this tokenID');
        if ( _trigger ) {
            rebase();
        }
        reSTACK.transferFrom( _nft, stakingTokenId, stakingTokenId, _amount );
        STACK.safeTransfer( msg.sender, _amount );
        emit LogUnstake(_nft, _amount);
    }

    /**
        @notice stakes bonds for the bonding contract
        @param _amount uint
     */
    function stakeBond ( uint _amount )
    external
    {
        require ( msg.sender == bondContract, 'Only bond contract' );
        STACK.safeTransferFrom( msg.sender, address(this), _amount );
        reSTACK.transfer(stakingTokenId, bondTokenId, _amount);
    }

    /**
        @notice enables erc721 receipt
        @param address
        @param address
        @param uint256
        @param bytes
        @return bytes4
     */
    function onERC721Received(address, address, uint256, bytes memory) public virtual override returns (bytes4) {
        return this.onERC721Received.selector;
    }

    /**
        @notice allows NFT owner to create a staking pool for others to join
        @param _nft uint32
        @param _fee uint sets deposit fee for outsiders in thousandths i.e. 5000 = 5% fee
        @param _minDays uint sets minimum time before owner can close the pool in days
        @param _amount uint amount pool owner can stake in same tx
     */
    function openPool ( uint32 _nft, uint _fee, uint _minDays, uint _amount )
    external 
    {   
        require ( _minDays > warmupPeriod, 'must be longer than warmup' );
        Pool memory pool = pools[ _nft ];
        require ( nftContract.ownerOf(_nft) == msg.sender, 'you do not own this tokenID' );
        nftContract.safeTransferFrom(msg.sender, address(this), uint(_nft));
        
        // pool terms
        pools[ _nft ] = Pool( msg.sender, _fee, block.timestamp + (_minDays * 1 days) );
        if (_amount > 0) {
            STACK.safeTransferFrom(msg.sender, address(this), _amount);
            reSTACK.transfer(stakingTokenId, _nft, _amount);
            poolers[_nft].push(Pooler(msg.sender, reSTACK.gonsForBalance(_amount + reSTACK.balanceOf(_nft))));
        }
        else {
            poolers[_nft].push(Pooler(msg.sender, reSTACK.gonsForBalance(reSTACK.balanceOf(_nft))));
        }
    }

    /**
        @notice lets outsiders join NFT staking pools
        @param _nft uint32
        @param _amount uint
     */
    function joinPool ( uint32 _nft, uint _amount) 
    external 
    {   
        Pool memory pool = pools[ _nft ];
        require ( pool.minTime != 0, 'NFT staking pool is not active' );
        STACK.safeTransferFrom(msg.sender, address(this), _amount);
        reSTACK.transfer(stakingTokenId, _nft, _amount);
        
        // fees for owner
        Pooler storage owner = poolers[_nft][0];
        if (pool.fee > 0) {
            uint tax = (pool.fee * _amount)/1e5;
            owner.gons += reSTACK.gonsForBalance(tax);
            poolers[_nft].push(Pooler(msg.sender, reSTACK.gonsForBalance(_amount - tax)));
        }
        else {
            poolers[_nft].push(Pooler(msg.sender, reSTACK.gonsForBalance(_amount)));
        }
    }

    /**
        @notice lets user leave pool
        @param _nft uint32 
     */
    function leavePool ( uint32 _nft )
    external 
    {   
        uint gons;
        Pool memory pool = pools[_nft];
        require (block.timestamp > pool.minTime, 'min pool time not reached');
        Pooler[] storage poolerz = poolers[_nft];
        for (uint i=0; i<poolerz.length; i++) {
            if (poolerz[i].pooler == msg.sender) {
                gons = poolerz[i].gons;
                delete poolerz[i];
            }
        }
        uint amount = reSTACK.balanceForGons(gons);
        reSTACK.transfer(_nft, stakingTokenId, amount);
        STACK.safeTransfer(msg.sender, amount);
    }

    /**
        @notice lets a pool owner close their pool
        @param _nft uint
     */
    function closePool ( uint32 _nft )
    external 
    {   
        Pool memory pool = pools[ _nft ];
        require (pool.minTime < block.timestamp, 'Pool is still active');
        require (pool.owner == msg.sender, 'You are not the owner');
        uint totalGons; 
        if (poolers[_nft].length > 1) {
            for (uint i=1; i<poolers[_nft].length; i++) {
            Pooler memory pooler = poolers[_nft][i];
            totalGons += pooler.gons;
            pooler.gons = reSTACK.balanceForGons(pooler.gons);
            }
        }
        reSTACK.transfer(_nft, stakingTokenId, reSTACK.balanceForGons(totalGons));
        nftContract.safeTransferFrom(address(this), msg.sender, uint(_nft));
    }

    /** 
        @notice lets poolers claim their stack when pool owner closes a pool
     */
    function stackClaim ()
    external {
        uint amount = stackClaims[msg.sender];
        require ( amount > 0, 'you have nothing to claim' );
        delete stackClaims[msg.sender];
        STACK.safeTransferFrom(address(this), msg.sender, amount);
    }


    /**
        @notice trigger rebase if epoch over
     */
    function rebase() 
    public 
    {
        if( epoch.endTime <= uint32(block.timestamp) ) {
            
            reSTACK.rebase( epoch.distribute, epoch.number );

            epoch.endTime += epoch.length;
            epoch.number++;
            
            if ( address(distributor) != address(0) ) {
                distributor.distribute();
            }

            uint balance = contractBalance();
            uint staked = reSTACK.circulatingSupply();

            if( balance <= staked ) {
                epoch.distribute = 0;
            } else {
                epoch.distribute = balance - staked;
            }
            emit LogRebase(epoch.distribute);
        }
    }


    /**
        @notice prevent new deposits to nft (protection from malicious activity)
     */
    function toggleDepositLock(uint32 _nft) 
    external 
    {
        require(nftContract.ownerOf(_nft) == msg.sender);
        warmupInfo[ _nft ].lock = !warmupInfo[ _nft ].lock;
        emit LogDepositLock(_nft, warmupInfo[ _nft ].lock);
    }

    /* ====== VIEW FUNCTIONS ====== */

    /**
        @notice returns contract STACK holdings, including bonuses provided
        @return uint
     */
    function contractBalance() 
    public view returns ( uint ) 
    {
        return STACK.balanceOf( address(this) );
    }

    /**
        @notice returns amount of rebasing stack in warmup
        @return uint
     */

    function supplyInWarmup ()
    external view returns (uint supply)
    {
        supply = reSTACK.balanceForGons(gonsInWarmup);
    }

    /**
        @notice returns the reSTACK index, which tracks rebase growth
        @return uint
     */
    function index() 
    external view returns ( uint ) 
    {
        return reSTACK.index();
    }

    /* ====== POLICY FUNCTIONS ====== */


    enum CONTRACTS { DISTRIBUTOR, NFT, BOND }
    /**
        @notice sets the contracts
        @param _contract address
     */
    function setContract( CONTRACTS _contract, address _address ) 
    external onlyOwner 
    {
        if( _contract == CONTRACTS.DISTRIBUTOR ) { // 0
            distributor = IDistributor(_address);
        } else if( _contract == CONTRACTS.NFT ) { // 1
            nftContract = INFT(_address);
        } else if( _contract == CONTRACTS.BOND ) { // 2
            bondContract = _address;
        emit LogSetContract(_contract, _address);
        }
    }


    /**
     * @notice set warmup period in epoch's numbers for new stakers
     * @param _warmupPeriod uint
     */
    function setWarmupPeriod( uint _warmupPeriod ) 
    external onlyOwner 
    {
        warmupPeriod = _warmupPeriod;
        emit LogWarmupPeriod(_warmupPeriod);
    }

}
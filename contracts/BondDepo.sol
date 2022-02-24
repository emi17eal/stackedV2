//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "hardhat/console.sol";
import './libraries/LowGasSafeMath.sol';
import '@openzeppelin/contracts/utils/Address.sol';
import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol';
import '@openzeppelin/contracts/token/ERC721/IERC721.sol';
import './types/IERC20NFTOwned.sol';
import '@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol';
import '@openzeppelin/contracts/token/ERC721/IERC721.sol';


interface INFT is IERC721 {
    function ownerOf(uint256 tokenId) external view override returns (address);
}

interface IDistributor {
    function distribute() external returns ( bool );
    function mintRewards( address _recipient, uint _amount ) external;
}

interface IStaking {
    function stakeBond (uint _amount) external;
}

interface IreSTACK is IERC20NFTOwned {
    function rebase( uint256 ohmProfit_, uint epoch_) external returns (uint256);

    function circulatingSupply() external view returns (uint256);

    function balanceOf(uint32 id) external view override returns (uint256);

    function gonsForBalance( uint amount ) external view returns ( uint );

    function balanceForGons( uint gons ) external view returns ( uint );
    
    function index() external view returns ( uint );
}

contract BondDepo is Ownable {

    /* BONDS FOR PRINCIPLES PAIRED WITH wETH ON UNISWAP */

    /* ======== EVENTS ======== */

    event BondCreated ( address principle, uint principleAmount, uint stackAmount, uint vestingTerm);

    /* ====== VARIABLES ====== */

    address public immutable stack;
    address public immutable wETH;
    address public immutable wethStackPair;
    address public immutable distributor;       // mints OHM when receives principle
    address public immutable treasury;               // receives profit share from bond
    
    uint32 public bondTokenId;
    IStaking public staking;
    INFT public nftContract;
    IreSTACK public reSTACK;
    

    mapping (address => BondTerms) public Bonds;     // tokens currently being bonded
    mapping (address => mapping(address => Bond)) public bondInfo;  // (principle => mapping(user => Bond))
    mapping (address => mapping(uint32 => Bond)) public stakedBondInfo;  // (principle => mapping(user => Bond))

    /* ====== STRUCTS ====== */

    struct BondTerms {
        address principle;                  // address of principle = token being bonded
        address pairAddress;                // address of uniswap eth pair
        uint stackAvailable;                // amount of stack available 
        uint minDiscount;                   // base rate for minimum vest in thousandths i.e. 5000 = 5%
        uint8 minimumVest;                  // minimum vesting period in days
    }

    // Info for bond holder
    struct Bond {
        address principle;                  // bond type
        uint payout;                        // stack remaining to be paid
        uint unlockTime;                    // Seconds left to vest
        uint timestamp;                     // Last interaction
        uint pricePaid;                     // In principle, for front end viewing
    }

    /* ====== CONSTRUCTOR ====== */

    constructor (
        address _stack, 
        address _reSTACK,
        address _wETH, 
        address _distributor, 
        address _treasury, 
        address _wethStackPair,
        uint32 _bondTokenId)
    {
        require ( _stack != address(0) );
        stack = _stack;
        require ( _reSTACK != address(0) );
        reSTACK = IreSTACK(_reSTACK);
        require ( _wETH != address(0) );
        wETH = _wETH;
        require ( _distributor != address(0) );
        distributor = _distributor;
        require ( _treasury != address(0) );
        treasury = _treasury;
        require ( _wethStackPair != address(0) );
        wethStackPair = _wethStackPair;
        bondTokenId = _bondTokenId;

    }

    /* ====== PUBLIC FUNCTIONS ====== */

    /**
        @notice takes principle token and vests equivalent stack
        @param _principle address of the token being bonded
        @param _principleAmount uint amount being bonded
        @param _minStackAmount uint minimum stack received to prevent slippage
        @param _vestingDays uint time chosen to vest by user
     */
    function buyBond (address _principle, uint _principleAmount, uint _minStackAmount, uint _vestingDays)
    external returns ( uint ) 
    {
        require ( _vestingDays >= Bonds[_principle].minimumVest, "minimum vesting period");

        // getting prices and applying discount
        uint wethAmount = getPrice( _principle, _principleAmount );
        uint discount = getDiscount ( _vestingDays, Bonds[_principle].minDiscount);
        wethAmount += (1e13 * discount * wethAmount)/1e18;
        uint stackAmount = wethToStack(wethAmount);
        require ( stackAmount >= _minStackAmount, 'Slippage'); 

        // adjust remaining
        Bonds[_principle].stackAvailable -= stackAmount;

        // transfers
        IERC20( _principle ).transferFrom( msg.sender, treasury, _principleAmount );

        // depositor info is stored
        bondInfo[_principle][ msg.sender ] = Bond({
            principle: _principle, 
            payout: bondInfo[_principle][ msg.sender ].payout += stackAmount,
            unlockTime: block.timestamp + _vestingDays * 1 days,
            timestamp: block.timestamp,
            pricePaid: bondInfo[_principle][ msg.sender ].pricePaid += _principleAmount
        });

        // indexed events are emitted
        emit BondCreated( _principle, _principleAmount, stackAmount, _vestingDays);

        return stackAmount; 
    }

    /**
        @notice sends stack to user if vesting period is over
        @param _principle address
     */
    function claimBond ( address _principle )
    external 
    {   
        Bond memory bond = bondInfo[_principle][msg.sender];
        require ( bond.payout > 0, 'No payout' );
        require ( bond.unlockTime <= block.timestamp, 'Your bond is still vesting' );
        delete bondInfo[_principle][msg.sender];
        IERC20( stack ).transfer( msg.sender, bond.payout );
    }

    /**
        @notice takes principle, then stakes and vests equivalent stack
        @param _principle address
        @param _nft uint32 id of NFT staked bond is assigned to
        @param _principleAmount uint
        @param _minStackAmount uint
        @param _vestingDays uint
     */
    function buyStakedBond (address _principle, uint32 _nft, uint _principleAmount, uint _minStackAmount, uint _vestingDays) 
    external returns (uint)
    {
        require ( nftContract.ownerOf(_nft) == msg.sender , 'You do not own this NFT' );
        require ( _vestingDays >= Bonds[_principle].minimumVest, "minimum vesting period");

        // getting prices and applying discount
        uint wethAmount = getPrice( _principle, _principleAmount );
        uint discount = getDiscount ( _vestingDays, Bonds[_principle].minDiscount);
        wethAmount += (1e13 * discount * wethAmount)/1e18;
        uint stackAmount = wethToStack(wethAmount);
        require ( stackAmount >= _minStackAmount, 'Slippage' ); 

        // adjust remaining
        Bonds[_principle].stackAvailable -= stackAmount;

        // transfers
        IERC20( _principle ).transferFrom( msg.sender, treasury, _principleAmount );

        // depositor info is stored
        stakedBondInfo[_principle][ _nft ] = Bond({
            principle: _principle, 
            payout: reSTACK.gonsForBalance(stackAmount),
            unlockTime: block.timestamp + _vestingDays * 1 days,
            timestamp: block.timestamp,
            pricePaid: stakedBondInfo[_principle][ _nft ].pricePaid += _principleAmount
        });

        // staking 
        staking.stakeBond(stackAmount);

        // indexed events are emitted
        emit BondCreated( _principle, _principleAmount, stackAmount, _vestingDays);

        return stackAmount;    

    }

    /**
        @notice sends rebasing stack to the nft
        @param _principle address
        @param _nft uint32
     */
    function claimStakedBond (address _principle, uint32 _nft)
    external
    {
        require ( nftContract.ownerOf(_nft) == msg.sender, 'You do not own this NFT' );
        Bond memory bond = stakedBondInfo[_principle][_nft];
        require ( bond.payout > 0, 'No payout' );
        require ( bond.unlockTime <= block.timestamp, 'Your bond is still vesting' );
        delete stakedBondInfo[_principle][_nft];
        reSTACK.transfer(bondTokenId, _nft, reSTACK.balanceForGons(bond.payout) );
    }

    /* ====== INTERNAL FUNCTIONS ====== */

    /**
        @notice returns price for (_amount * principle) in wETH
        @param _principle address
        @param _amount uint
        @return uint
     */
    function getPrice (address _principle, uint _amount)
    internal view returns ( uint price ) 
    {
        IUniswapV2Pair pair = IUniswapV2Pair( Bonds[_principle].pairAddress );
        (uint Res0, uint Res1,) = pair.getReserves();
        uint8 decimals = getDecimals(_principle);

        uint principleRes = pair.token0() == _principle ? 
        Res0*(10**(18-decimals)) : Res1*(10**(18-decimals));

        uint weth = pair.token0() == wETH ? Res0 : Res1;
        price = (_amount*weth)/principleRes;                       
    }

    /**
        @notice returns discount based on vesting period
        @param _daysVesting uint
        @param _rate uint
        @return uint
     */
    function getDiscount (uint _daysVesting, uint _rate) 
    internal pure returns ( uint discount ) 
    {   
        require(_daysVesting >= 7, "Minimum 7 days vesting");
        uint multiplier;
        
        if (7 <= _daysVesting && _daysVesting < 14) {
            multiplier = (1e5*_daysVesting/14) + 50000;
        }
        if (14 <= _daysVesting && _daysVesting < 28) {
            multiplier = (3*1e5*_daysVesting/56) + 75000;
        }
        if (28 <= _daysVesting && _daysVesting < 56) {
            multiplier = (9*1e5*_daysVesting/448) + 112500;
        }
        if (56 <= _daysVesting && _daysVesting < 112) {
            multiplier = (27*1e5*_daysVesting/896) + 168750;
        }
        discount = (multiplier*_rate)/1e5; 

    }

    /**
        @notice returns weth amount in stack
        @param _wethAmount uint
        @return uint
     */    
    function wethToStack (uint _wethAmount)
    internal view returns ( uint )
    {
        IUniswapV2Pair pair = IUniswapV2Pair( wethStackPair ); 
        (uint Res0, uint Res1,) = pair.getReserves();
        uint stack18decimals = pair.token0() == stack ? Res0*1e9 : Res1*1e9;        // converting 9 decimals to 18
        uint principle = pair.token0() == stack ? Res1 : Res0;                      
        return((_wethAmount*stack18decimals)/principle)/1e9;                        // return amount of token0 needed to buy token1
    }

    /**
        @notice returns decimals of a token
        @param _principle address
        @return uint8
     */
    function getDecimals (address _principle)
    internal view returns ( uint8 )
    {
        IERC20Metadata principle = IERC20Metadata( _principle );
        try principle.decimals() returns(uint8 decimals) {
            return(decimals);
        } catch {
            return (18);
        }
    }
    /* ====== POLICY FUNCTINS ====== */

    /**
        @notice mints stack to this contract and opens up a new bond
        @param _principle address
        @param _uniPairAddress address of the uniswap weth pair for the principle
        @param _stackAvailable uint how much stack is available for bonds
        @param _rate uint base rate for minimum vest in thousandths i.e. 5000 = 5%
        @param _minimumVest uint8 minimum vest term in days
     */
    function createBond (
        address _principle,
        address _uniPairAddress,
        uint _stackAvailable,
        uint _rate,
        uint8 _minimumVest)
    external onlyOwner 
    {   
        require ( Bonds[_principle].stackAvailable == 0, 'there is still bonds available' ); 
        Bonds[_principle] = BondTerms(_principle, _uniPairAddress, _stackAvailable, _rate, _minimumVest);
        IDistributor( distributor ).mintRewards( address(this), _stackAvailable );
    }

    /**
        @notice closes bond 
        @param _principle address
     */
    function deleteBond ( address _principle )
    external onlyOwner 
    {
        delete Bonds[_principle];
    }

    /**
        @notice sets nft contract
        @param _nftContract address
     */
    function setNftContract (address _nftContract)
    external onlyOwner
    {
        nftContract = INFT(_nftContract);
    }

    /**
        @notice sets staking contract
        @param _staking address
     */
    function setStakingContract (address _staking)
    external onlyOwner
    {
        staking = IStaking(_staking);
    }    

    /**
        @notice approves an external stack spender 
        @param _spender address
        @param _amount uint
     */
    function setApproval (address _spender, uint _amount)
    external onlyOwner 
    {
        IERC20( stack ).approve(_spender, _amount);

    }
}
//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Creator: eo @emiliolanzalaco

import "hardhat/console.sol";
import './libraries/LowGasSafeMath.sol';
import '@openzeppelin/contracts/access/Ownable.sol';
import "./types/ERC721A.sol";
import './types/IERC20NFTOwned.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

contract NFTContract is ERC721A, Ownable {

    using SafeERC20 for IERC20;

    /* ====== VARIABLES ====== */

    // mapping the erc20 balances belonging to each erc721
    mapping (uint32 => mapping(address => uint)) erc20Balances;
    mapping (address => bool) public allowedTokens;
    
    mapping (address => bool) public whitelistMinted;
    uint public devMint;
    bytes32 public rootHash;
    string private _baseTokenURI;

    /* ====== STRUCTS ====== */

    struct SaleConfig {
        uint32 whitelistSaleStartTime;
        uint32 publicSaleStartTime;
        uint64 whitelistPrice;
        uint64 publicPrice;
    }
    SaleConfig public saleConfig;

    /* ====== CONSTRUCTOR ====== */
    
    constructor(
        bytes32 _rootHash,
        uint32 _whitelistSaleStartTime,
        uint32 _publicSaleStartTime,
        uint64 _whitelistPrice,
        uint64 _publicPrice) ERC721A("rebaseNFT", "rebaseNFT") {
        rootHash = _rootHash;
        saleConfig.whitelistSaleStartTime = _whitelistSaleStartTime;
        saleConfig.publicSaleStartTime = _publicSaleStartTime;
        saleConfig.whitelistPrice = _whitelistPrice;
        saleConfig.publicPrice = _publicPrice;
    }

    /* ====== PUBLIC FUNCTIONS ====== */


    // need to add max 
    function whitelistMint(uint _quantity, bytes32[] memory _proof) external payable {
        require( msg.value >= saleConfig.whitelistPrice * _quantity, 'Not enough ETH' );
        require( block.timestamp >= saleConfig.whitelistSaleStartTime, 'Whitelist sale not started');
        require( !whitelistMinted[msg.sender], "You have already minted" );
        require( whitelistValidated(_proof), "You are not on the whitelist" );
        _safeMint( msg.sender, _quantity );
    }

    function teamMint(uint _quantity) external onlyOwner {
        _safeMint( msg.sender, _quantity );
    }

    function publicMint(uint _quantity) external payable {
        require( msg.value >= saleConfig.publicPrice * _quantity, 'Not enough ETH' );
        require( block.timestamp >= saleConfig.publicSaleStartTime, 'Public sale not started');
        _safeMint( msg.sender, _quantity );
    }

    function depositERC20(uint32 _tokenID, uint _amount, address _address) external {
        require( ownerOf( _tokenID ) == msg.sender, 'you do not own this tokenID' );
        require( allowedTokens[_address], 'deposits of this token are not allowed' );
        require( _amount > 0, 'must deposit more than zero' );
        require( ownerOf( _tokenID ) == msg.sender, 'you do not own this tokenID' );
        IERC20 token = IERC20(_address);
        token.transferFrom(msg.sender, address(this), _amount);
        erc20Balances[_tokenID][_address] += _amount;
    }
    
    function withdrawERC20(uint32 _tokenID, uint _amount, address _address) external {
        require( ownerOf( _tokenID ) == msg.sender, 'you do not own this tokenID' );
        require( _amount > 0, 'must deposit more than zero' );
        require( erc20Balances[_tokenID][_address] >= _amount, 'the balance of this token is not great enough' );
        erc20Balances[_tokenID][_address] -= _amount;
        IERC20 token = IERC20(_address);
        token.transfer(msg.sender, _amount); 
    }

    /* ====== VIEW FUNCTIONS ====== */

    // Get ERC20 balances of an NFT
    function getTokenBalance(uint32 _tokenID, address _address) public view returns(uint balance) {
        balance = erc20Balances[_tokenID][_address];
    }

    function whitelistValidated(bytes32[] memory _proof) internal view returns (bool) {
        // Compute the merkle root
        bytes32 leaf = keccak256(abi.encodePacked(msg.sender));
        if (MerkleProof.verify(_proof, rootHash, leaf)) {
            // Mark as claimed
            whitelistMinted[msg.sender];
            return true;
        }
        else {
            return false;
        }
    }

    function _baseURI() internal view virtual override returns (string memory) {
        return _baseTokenURI;
    }

    /* ====== POLICY FUNCTIONS ====== */

    function setBaseURI(string calldata baseURI) external onlyOwner {
        _baseTokenURI = baseURI;
    }

    function withdrawEth() external onlyOwner {
        (bool success, ) = msg.sender.call{value: address(this).balance}("");
        require(success, "Transfer failed.");
    }

}
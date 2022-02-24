// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v4.5.0) (token/ERC20/ERC20.sol)

pragma solidity ^0.8.0;

import "./IERC20NFTOwned.sol";
import "./IERC20Metadata.sol";
import '@openzeppelin/contracts/token/ERC721/IERC721.sol';

/**
 * @dev Implementation of the {IERC20} interface.
 *
 * This implementation is agnostic to the way tokens are created. This means
 * that a supply mechanism has to be added in a derived contract using {_mint}.
 * For a generic mechanism see {ERC20PresetMinterPauser}.
 *
 * TIP: For a detailed writeup see our guide
 * https://forum.zeppelin.solutions/t/how-to-implement-erc20-supply-mechanisms/226[How
 * to implement supply mechanisms].
 *
 * We have followed general OpenZeppelin Contracts guidelines: functions revert
 * instead returning `false` on failure. This behavior is nonetheless
 * conventional and does not conflict with the expectations of ERC20
 * applications.
 *
 * Additionally, an {Approval} event is emitted on calls to {transferFrom}.
 * This allows applications to reconstruct the allowance for all accounts just
 * by listening to said events. Other implementations of the EIP may not emit
 * these events, as it isn't required by the specification.
 *
 * Finally, the non-standard {decreaseAllowance} and {increaseAllowance}
 * functions have been added to mitigate the well-known issues around setting
 * allowances. See {IERC20-approve}.
 */
contract ERC20NFTOwned is IERC20NFTOwned, IERC20Metadata {
    mapping(uint32 => uint256) private _balances;

    mapping(uint32 => mapping(uint32 => uint256)) private _allowances;  // mapping( ownerId => mapping( spenderId => amount))

    uint256 internal _totalSupply;

    IERC721 public immutable nftContract;

    string private _name;
    string private _symbol;

    /**
     * @dev Sets the values for {name} and {symbol}.
     *
     * The default value of {decimals} is 18. To select a different value for
     * {decimals} you should overload it.
     *
     * All two of these values are immutable: they can only be set once during
     * construction.
     */
    constructor(string memory name_, string memory symbol_, address nftContract_) {
        _name = name_;
        _symbol = symbol_;
        nftContract = IERC721(nftContract_);
    }

    /**
     * @dev Returns the name of the token.
     */
    function name() public view virtual override returns (string memory) {
        return _name;
    }

    /**
     * @dev Returns the symbol of the token, usually a shorter version of the
     * name.
     */
    function symbol() public view virtual override returns (string memory) {
        return _symbol;
    }

    /**
     * @dev Returns the number of decimals used to get its user representation.
     * For example, if `decimals` equals `2`, a balance of `505` tokens should
     * be displayed to a user as `5.05` (`505 / 10 ** 2`).
     *
     * Tokens usually opt for a value of 18, imitating the relationship between
     * Ether and Wei. This is the value {ERC20} uses, unless this function is
     * overridden;
     *
     * NOTE: This information is only used for _display_ purposes: it in
     * no way affects any of the arithmetic of the contract, including
     * {IERC20-balanceOf} and {IERC20-transfer}.
     */
    function decimals() public view virtual override returns (uint8) {
        return 18;
    }

    /**
     * @dev See {IERC20-totalSupply}.
     */
    function totalSupply() public view virtual override returns (uint256) {
        return _totalSupply;
    }

    /**
     * @dev See {IERC20-balanceOf}.
     */
    function balanceOf(uint32 id) public view virtual override returns (uint256) {
        return _balances[id];
    }

    /**
     * @dev See {IERC20-transfer}.
     *
     * Requirements:
     *
     * - `to` cannot be the zero address.
     * - the caller must have a balance of at least `amount`.
     */
    function transfer(uint32 fromId, uint32 toId, uint256 amount) public virtual override returns (bool) {
        require (nftContract.ownerOf(fromId) == msg.sender, "You do not own this tokenId" );
        _transfer(fromId, toId, amount);
        return true;
    }

    /**
     * @dev See {IERC20-allowance}.
     */
    function allowance(uint32 ownerId, uint32 spenderId) public view virtual override returns (uint256) {
        return _allowances[ownerId][spenderId];
    }

    /**
     * @dev See {IERC20-approve}.
     *
     * NOTE: If `amount` is the maximum `uint256`, the allowance is not updated on
     * `transferFrom`. This is semantically equivalent to an infinite approval.
     *
     * Requirements:
     *
     * - `spender` cannot be the zero address.
     */
    function approve(uint32 ownerId, uint32 spenderId, uint256 amount) public virtual override returns (bool) {
        require (nftContract.ownerOf(ownerId) == msg.sender, "You do not own this tokenId" );
        _approve(ownerId, spenderId, amount);
        return true;
    }

    /**
     * @dev See {IERC20-transferFrom}.
     *
     * Emits an {Approval} event indicating the updated allowance. This is not
     * required by the EIP. See the note at the beginning of {ERC20}.
     *
     * NOTE: Does not update the allowance if the current allowance
     * is the maximum `uint256`.
     *
     * Requirements:
     *
     * - `from` and `to` cannot be the zero address.
     * - `from` must have a balance of at least `amount`.
     * - the caller must have allowance for ``from``'s tokens of at least
     * `amount`.
     */
    function transferFrom(
        uint32 fromId,
        uint32 toId,
        uint32 spenderId,
        uint256 amount
    ) public virtual override returns (bool) {
        require (nftContract.ownerOf(spenderId) == msg.sender, "You do not own this tokenId" );
        _spendAllowance(fromId, spenderId, amount);
        _transfer(fromId, toId, amount);
        return true;
    }

    /**
     * @dev Atomically increases the allowance granted to `spender` by the caller.
     *
     * This is an alternative to {approve} that can be used as a mitigation for
     * problems described in {IERC20-approve}.
     *
     * Emits an {Approval} event indicating the updated allowance.
     *
     * Requirements:
     *
     * - `spender` cannot be the zero address.
     */
    function increaseAllowance(uint32 ownerId, uint32 spenderId, uint256 addedValue) public virtual returns (bool) {
        require (nftContract.ownerOf(ownerId) == msg.sender, "You do not own this tokenId" );
        _approve(ownerId, spenderId, _allowances[ownerId][spenderId] + addedValue);
        return true;
    }

    /**
     * @dev Atomically decreases the allowance granted to `spender` by the caller.
     *
     * This is an alternative to {approve} that can be used as a mitigation for
     * problems described in {IERC20-approve}.
     *
     * Emits an {Approval} event indicating the updated allowance.
     *
     * Requirements:
     *
     * - `spender` cannot be the zero address.
     * - `spender` must have allowance for the caller of at least
     * `subtractedValue`.
     */
    function decreaseAllowance(uint32 ownerId, uint32 spenderId, uint256 subtractedValue) public virtual returns (bool) {
        require (nftContract.ownerOf(ownerId) == msg.sender, "You do not own this tokenId" );
        uint256 currentAllowance = _allowances[ownerId][spenderId];
        require(currentAllowance >= subtractedValue, "ERC20: decreased allowance below zero");
        unchecked {
            _approve(ownerId, spenderId, currentAllowance - subtractedValue);
        }

        return true;
    }

    /**
     * @dev Moves `amount` of tokens from `sender` to `recipient`.
     *
     * This internal function is equivalent to {transfer}, and can be used to
     * e.g. implement automatic token fees, slashing mechanisms, etc.
     *
     * Emits a {Transfer} event.
     *
     * Requirements:
     *
     * - `from` cannot be the zero address.
     * - `to` cannot be the zero address.
     * - `from` must have a balance of at least `amount`.
     */
    function _transfer(
        uint32 fromId,
        uint32 toId,
        uint256 amount
    ) internal virtual {
        require(nftContract.ownerOf(fromId) != address(0), "ERC20: transfer from non-existent tokenId");
        require(nftContract.ownerOf(toId) != address(0), "ERC20: transfer to non-existent token");

        _beforeTokenTransfer(fromId, toId, amount);

        uint256 fromBalance = _balances[fromId];
        require(fromBalance >= amount, "ERC20: transfer amount exceeds balance");
        unchecked {
            _balances[fromId] = fromBalance - amount;
        }
        _balances[toId] += amount;

        emit Transfer(fromId, toId, amount);

        _afterTokenTransfer(fromId, toId, amount);
    }

    /** @dev Creates `amount` tokens and assigns them to `account`, increasing
     * the total supply.
     *
     * Emits a {Transfer} event with `from` set to the zero address.
     *
     * Requirements:
     *
     * - `account` cannot be the zero address.
     */
    function _mint(uint32 toId, uint256 amount) internal virtual {
        require(nftContract.ownerOf(toId) != address(0), "ERC20: mint to the zero address");

        _beforeTokenMint(toId, amount);

        _totalSupply += amount;
        _balances[toId] += amount;
        emit Mint(toId, amount);

    }

    /**
     * @dev Destroys `amount` tokens from `account`, reducing the
     * total supply.
     *
     * Emits a {Transfer} event with `to` set to the zero address.
     *
     * Requirements:
     *
     * - `account` cannot be the zero address.
     * - `account` must have at least `amount` tokens.
     */
    function _burn(uint32 fromId, uint256 amount) internal virtual {
        require(nftContract.ownerOf(fromId) != address(0), "ERC20: burn from the zero address");

        _beforeTokenBurn(fromId, amount);

        uint256 idBalance = _balances[fromId];
        require(idBalance >= amount, "ERC20: burn amount exceeds balance");
        unchecked {
            _balances[fromId] = idBalance - amount;
        }
        _totalSupply -= amount;

        emit Burn(fromId, amount);

    }

    /**
     * @dev Sets `amount` as the allowance of `spender` over the `owner` s tokens.
     *
     * This internal function is equivalent to `approve`, and can be used to
     * e.g. set automatic allowances for certain subsystems, etc.
     *
     * Emits an {Approval} event.
     *
     * Requirements:
     *
     * - `owner` cannot be the zero address.
     * - `spender` cannot be the zero address.
     */
    function _approve(
        uint32 ownerId,
        uint32 spenderId,
        uint256 amount
    ) internal virtual {
        require(nftContract.ownerOf(ownerId) != address(0), "ERC20: approve from the zero address");
        require(nftContract.ownerOf(spenderId) != address(0), "ERC20: approve to the zero address");

        _allowances[ownerId][spenderId] = amount;
        emit Approval(ownerId, spenderId, amount);
    }

    /**
     * @dev Spend `amount` form the allowance of `owner` toward `spender`.
     *
     * Does not update the allowance amount in case of infinite allowance.
     * Revert if not enough allowance is available.
     *
     * Might emit an {Approval} event.
     */
    function _spendAllowance(
        uint32 ownerId,
        uint32 spenderId,
        uint256 amount
    ) internal virtual {
        uint256 currentAllowance = allowance(ownerId, spenderId);
        if (currentAllowance != type(uint256).max) {
            require(currentAllowance >= amount, "ERC20: insufficient allowance");
            unchecked {
                _approve(ownerId, spenderId, currentAllowance - amount);
            }
        }
    }

    /**
     * @dev Hook that is called before any transfer of tokens. This includes
     * minting and burning.
     *
     * Calling conditions:
     *
     * - when `from` and `to` are both non-zero, `amount` of ``from``'s tokens
     * will be transferred to `to`.
     * - when `from` is zero, `amount` tokens will be minted for `to`.
     * - when `to` is zero, `amount` of ``from``'s tokens will be burned.
     * - `from` and `to` are never both zero.
     *
     * To learn more about hooks, head to xref:ROOT:extending-contracts.adoc#using-hooks[Using Hooks].
     */
    function _beforeTokenTransfer(
        uint32 fromId,
        uint32 toId,
        uint256 amount
    ) internal virtual {}

    /**
     * @dev Hook that is called after any transfer of tokens. This includes
     * minting and burning.
     *
     * Calling conditions:
     *
     * - when `from` and `to` are both non-zero, `amount` of ``from``'s tokens
     * has been transferred to `to`.
     * - when `from` is zero, `amount` tokens have been minted for `to`.
     * - when `to` is zero, `amount` of ``from``'s tokens have been burned.
     * - `from` and `to` are never both zero.
     *
     * To learn more about hooks, head to xref:ROOT:extending-contracts.adoc#using-hooks[Using Hooks].
     */
    function _afterTokenTransfer(
        uint32 from,
        uint32 to,
        uint256 amount
    ) internal virtual {}

    function _beforeTokenMint(
        uint32 toId,
        uint256 amount
    ) internal virtual {}

    function _beforeTokenBurn(
        uint32 fromId,
        uint256 amount
    ) internal virtual {}
}

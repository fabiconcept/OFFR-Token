// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/access/AccessControl.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/ERC20.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/utils/Context.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/utils/math/SafeMath.sol";
import "./math/SafeMathInt.sol";
import "./math/SafeMathUint.sol";
import "./uniswap/IUniswapV2Router02.sol";

contract OffrToken is Context, AccessControl, IERC20 {
    using SafeMath for uint256;
    using SafeMathUint for uint256;
    using SafeMathInt for int256;

    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    address payable public owner;
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;

    uint256 private _totalSupply;
    string private _name;
    string private _symbol;
    uint8 private _decimals;

    uint256 public _rate;
    uint256 public _cap;
    address public _beneficiary;

    uint256 private constant magnitude = 2**128;

    address[] public holderList;

    event AmountPaidOut(address indexed tokenholder, uint256 amountUSDC);

    constructor(
        string memory name_,
        string memory symbol_,
        uint8 decimals_,
        uint256 cap_,
        uint256 rate_,
        address beneficiary_
    ) {
        _setupRole(MINTER_ROLE, _msgSender());
        _name = name_;
        _symbol = symbol_;
        _decimals = decimals_;
        require(rate_ > 0, "rate is 0");
        require(cap_ > 0, "cap is 0");
        require(beneficiary_ != address(0), "address is null");
        _cap = cap_;
        _rate = rate_;
        _beneficiary = beneficiary_;

        owner = payable(msg.sender);
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Only the Owner can call this function");
        _;
    }

    function transferOwnership(address newOwner) public onlyOwner {
        require(newOwner != address(0), "Invalid new owner address.");
        owner = payable(newOwner);
    }

    function name() public view returns (string memory) {
        return _name;
    }

    function symbol() public view returns (string memory) {
        return _symbol;
    }

    function getHolderList() public view returns (address[] memory) {
        return holderList;
    }

    function decimals() public view returns (uint8) {
        return _decimals;
    }

    function cap() public view returns (uint256) {
        return _cap;
    }

    function rate() public view returns (uint256) {
        return _rate;
    }

    function totalSupply() public view override returns (uint256) {
        return _totalSupply;
    }

    function getBeneficiary() public view returns (address) {
        return _beneficiary;
    }

    function balanceOf(address account) public view override returns (uint256) {
        return _balances[account];
    }

    function transfer(address recipient, uint256 amount)
        public
        virtual
        override
        returns (bool)
    {
        _transfer(_msgSender(), recipient, amount);
        return true;
    }

    function allowance(address ownerAddress, address spenderAddress)
        public
        view
        virtual
        override
        returns (uint256)
    {
        return _allowances[ownerAddress][spenderAddress];
    }

    function approve(address spender, uint256 amount)
        public
        virtual
        override
        returns (bool)
    {
        _approve(_msgSender(), spender, amount);
        return true;
    }

    function _burn(address account, uint256 amount) internal virtual {

        require(account != address(0), "ERC20: burn from the zero address");

        _beforeTokenTransfer(account, amount);

        uint256 accountBalance = _balances[account];
        require(accountBalance >= amount, "ERC20: burn amount exceeds balance");
        unchecked {
            _balances[account] = accountBalance - amount;
            // Overflow not possible: amount <= accountBalance <= totalSupply.
            _totalSupply -= amount;
        }

        emit Transfer(account, address(0), amount);
    }

    function addMinter (address newMinter) public onlyOwner {
        _setupRole(MINTER_ROLE, newMinter);
    }

    function burn(address account, uint256 amount) public {
        require(account != address(0), "can't burn from zero account");
        require(
            hasRole(MINTER_ROLE, _msgSender()),
            "must have minter role to mint"
        );

        _burn(account, amount);
    }

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) public virtual override returns (bool) {
        _transfer(sender, recipient, amount);
        _approve(
            sender,
            _msgSender(),
            _allowances[sender][_msgSender()].sub(
                amount,
                "transfer amount exceeds allowance"
            )
        );
        return true;
    }

    function _transfer(
        address sender,
        address recipient,
        uint256 amount
    ) internal virtual {
        require(sender != address(0), "transfer from the zero address");
        require(recipient != address(0), "transfer to the zero address");

        _beforeTokenTransfer(sender, amount);

        uint256 senderBalance = _balances[sender];
        require(senderBalance >= amount, "transfer amount exceeds balance");

        _balances[sender] = senderBalance.sub(amount);

        addHolder(recipient);

        if (senderBalance == amount) {
            removeHolder(sender);
        }

        _balances[recipient] = _balances[recipient].add(amount);

        emit Transfer(sender, recipient, amount);
    }


    function removeHolder(address holder) public {
        require(
            hasRole(MINTER_ROLE, _msgSender()),
            "must have minter role to mint"
        );
        for (uint256 i = 0; i < holderList.length; i++) {
            if (holderList[i] == holder) {
                holderList[i] = holderList[holderList.length - 1];
                holderList.pop();
                break;
            }
        }
    }

    function _mint(address account, uint256 amount) internal virtual {
        require(account != address(0), "mint to the zero address");

        _beforeTokenTransfer(address(0), amount);

        _totalSupply = _totalSupply.add(amount);
        _balances[account] = _balances[account].add(amount);
        emit Transfer(address(0), account, amount);
    }

    function _approve(
        address ownerOfToken,
        address spender,
        uint256 amount
    ) internal virtual {
        require(ownerOfToken != address(0), "approve from the zero address");
        require(spender != address(0), "approve to the zero address");

        _allowances[ownerOfToken][spender] = amount;
        emit Approval(ownerOfToken, spender, amount);
    }

    function addHolder(address newHolder) public {
        require(
            hasRole(MINTER_ROLE, _msgSender()),
            "must have minter role to mint"
        );
        // Check if the wallet address already exists in the holderList array
        bool alreadyExists = false;
        for (uint256 i = 0; i < holderList.length; i++) {
            if (holderList[i] == newHolder) {
                alreadyExists = true;
                break;
            }
        }

        // If the wallet address does not exist, add it to the holderList array
        if (!alreadyExists) {
            holderList.push(newHolder);
        }
    }

    function holderListLength() public view returns (uint256) {
        return holderList.length;
    }

    receive() external payable {}

    function mint(address to, uint256 amount) internal {
        require(
            hasRole(MINTER_ROLE, _msgSender()),
            "must have minter role to mint"
        );
        _mint(to, amount);
    }

    function sendTokens(address buyer, uint256 amount) public {
        require(buyer != address(0), "buyer is a zero address");
        require(amount != 0, "weiAmount is 0");

        uint256 tokens = amount.mul(_rate);

        mint(buyer, tokens);
    }

    function _beforeTokenTransfer(address from, uint256 amount)
        internal
        virtual
    {
        if (from == address(0)) {
            // When minting tokens, check the sale cap
            require(totalSupply().add(amount) <= _cap, "cap exceeded");
        }
    }
}

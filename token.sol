// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/security/Pausable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/access/AccessControl.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/utils/math/SafeMath.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/ERC20.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/utils/Context.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/security/ReentrancyGuard.sol";
import "./math/SafeMathInt.sol";
import "./math/SafeMathUint.sol";
import "./uniswap/IUniswapV2Router02.sol";

contract OffrToken is Context, AccessControl, IERC20, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeMathUint for uint256;
    using SafeMathInt for int256;

    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant KYC_ROLE = keccak256("KYC_ROLE");

    address payable public owner;
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;

    uint256 private _totalSupply;
    string private _name;
    string private _symbol;
    uint8 private _decimals;

    uint256 private _rate;
    uint256 private _cap;
    address private _beneficiary;

    uint256 private constant magnitude = 2**128;
    bool private isDividendPaymentPeriod = false;

    // KYC tracking Variables
    address[] private _kycUsers;
    mapping(address => bool) private _isKYCed;
    mapping(address => uint256) private _userIndices;
    mapping(address => bool) private _ownsTokens;

    event KYCUserAdded(address indexed userAddress);
    event KYCUserRemoved(address indexed userAddress);
    event Burn(address indexed burner, uint256 amount);
    
    constructor(
        string memory name_,
        string memory symbol_,
        uint8 decimals_,
        uint256 cap_,
        uint256 rate_,
        address beneficiary_
    ) {
        _setupRole(MINTER_ROLE, _msgSender());
        _setupRole(KYC_ROLE, msg.sender);

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

    
    function addMinter(address newMinter) external onlyOwner nonReentrant {
        _setupRole(MINTER_ROLE, newMinter);
    }

    function name() public view returns (string memory) {
        return _name;
    }

    function viewOwner() public view returns (address) {
        return owner;
    }

    function symbol() public view returns (string memory) {
        return _symbol;
    }

    function getKYCList() public view returns (address[] memory) {
        return _kycUsers;
    }

    function getDividendPaymentPeriodState () public view returns (bool){
        return isDividendPaymentPeriod;
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

    function kycUsersListLength() public view returns (uint256) {
        return _kycUsers.length;
    }

    function getOwnedTokens(address _stakeHolder) public view returns(bool){
        return _ownsTokens[_stakeHolder];
    }


    function transfer(address recipient, uint256 amount)
        public
        virtual
        override
        returns (bool)
    {
        require(!isDividendPaymentPeriod, "Dividend Period is ongoing, all transfers will resume after dividend period.");
        require(_isKYCed[msg.sender], "Sender is not KYCed");
        require(_isKYCed[recipient], "Recipient is not KYCed");

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

        if(_balances[account] == 0){
            _ownsTokens[account] = false;
        }

        emit Transfer(account, address(0), amount);
    }

    function burnMyBalance (address _tokenOwner, uint256 _amount) onlyRole(MINTER_ROLE) public returns (bool) {
        _burn(_tokenOwner, _amount);

        emit Burn(_tokenOwner, _amount);
        return true;
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

        require(sender != owner, "Cannot transfer tokens to token owner");
        require(recipient != owner, "Cannot transfer tokens to token owner");


        _beforeTokenTransfer(sender, amount);

        uint256 senderBalance = balanceOf(sender);
        require(senderBalance >= amount, "transfer amount exceeds balance");

        _balances[sender] = senderBalance.sub(amount);
        // Update _ownsTokens mapping for both sender and recipient
        _ownsTokens[msg.sender] = _balances[msg.sender] - amount > 0;
        _ownsTokens[recipient] = true;

        _balances[recipient] = _balances[recipient].add(amount);

        emit Transfer(sender, recipient, amount);
    }

    function updateOwnsToken(address stakeHolder) public nonReentrant {
        require(
            hasRole(MINTER_ROLE, _msgSender()),
            "must have minter role to use this function"
        );
        _ownsTokens[stakeHolder] = true;
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

    receive() external payable {}

    function mint(address to, uint256 amount) internal {
        require(
            hasRole(MINTER_ROLE, _msgSender()),
            "must have minter role to mint"
        );
        _mint(to, amount);
    }

    function sendTokens(address buyer, uint256 amount) onlyRole(MINTER_ROLE) public nonReentrant {
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

    function addKYCUser(address user) public nonReentrant onlyRole(KYC_ROLE) {
        require(user != address(0), "Invalid address");
        require(!_isKYCed[user], "User is already KYCed");

        // Add the user to the KYC list
        _isKYCed[user] = true;
        _kycUsers.push(user);
        _userIndices[user] = _kycUsers.length - 1;

        // Mark that the user does not own any tokens
        _ownsTokens[user] = false;

        // Emit an event to notify external systems of the change
        emit KYCUserAdded(user);
    }

    function removeKYCUser(address user)
        public
        nonReentrant
        onlyRole(KYC_ROLE)
    {
        require(_isKYCed[user], "User is not KYCed");

        // Check if user owns any tokens
        require(
            !_ownsTokens[user],
            "User owns tokens, cannot remove from KYC list"
        );

        // Get the index of the user in the _kycUsers array
        uint256 index = _userIndices[user];
        require(
            index < _kycUsers.length && _kycUsers[index] == user,
            "User not found in KYC list"
        );

        // Swap the user to remove with the last user in the array
        address lastUser = _kycUsers[_kycUsers.length - 1];
        _kycUsers[index] = lastUser;
        _userIndices[lastUser] = index;

        // Remove the last user from the array
        _kycUsers.pop();

        // Update the _isKYCed mapping
        _isKYCed[user] = false;
        _userIndices[user] = 0;

        // Emit an event to notify external systems of the change
        emit KYCUserRemoved(user);
    }

    function isKYCed(address _stakeHolder) public view returns (bool) {
        return _isKYCed[_stakeHolder];
    }

    function updateDividendPeriodStatus(bool state) public onlyRole(MINTER_ROLE) nonReentrant {
        isDividendPaymentPeriod = state;
    }
}
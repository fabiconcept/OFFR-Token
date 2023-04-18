// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/security/Pausable.sol";
import "./token.sol";

interface IUSDC {
    function balanceOf(address account) external view returns (uint256);

    function transfer(address recipient, uint256 amount)
        external
        returns (bool);

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external returns (bool);

    function approve(address spender, uint256 amount) external returns (bool);

    function allowance(address owner, address spender)
        external
        view
        returns (uint256);
}

contract TokenHandler is AccessControl, Pausable, ReentrancyGuard {
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    OffrToken public token;
    

    using SafeMath for uint256;
    using SafeMathUint for uint256;
    using SafeMathInt for int256;

    address payable public admin;

    address internal constant UNISWAP_ROUTER_ADDRESS =
        0x7aa3103351aD2E508b8f91E7422F96b397075B3d;
    IUniswapV2Router02 public _uniswapRouter;
    address private _usdcToken = 0xD3077255bE7183a690E2E1Af77581DC5303D3D04;
    IUSDC public _usdcInstance;

    uint256 private tokenSold = 0;

    string private saleBatchName;
    uint256 private saleEndDate;
    bool private saleIsActive;
    bool public fundingReleased = false;
    uint256 public startTimestamp;

    event TokensPurchased(
        address indexed transmitter,
        address indexed buyer,
        uint256 amountUSDC,
        uint256 amountToken
    );

    event FundsReleased(address indexed beneficiary, uint256 amountUSDC);
    event TokenSaleStarted(uint256 indexed _startDate, uint256 _endDate);
    event TokenSaleEnded(string indexed _batchName, uint256 _tokenSold);

    constructor(OffrToken _token) {
        admin = payable(msg.sender);
        token = _token;
        _usdcInstance = IUSDC(_usdcToken);
        _uniswapRouter = IUniswapV2Router02(UNISWAP_ROUTER_ADDRESS);
        _setupRole(PAUSER_ROLE, msg.sender);
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    modifier onlyAdmin() {
        require(msg.sender == admin, "Only the Owner can call this function");
        _;
    }

    function getName() public view returns (string memory) {
        return token.name();
    }

    function isDividendPaymentPeriodActive() public view returns (bool) {
        return token.getDividendPaymentPeriodState();
    }

    function getSaleEndDate() public view returns (uint256) {
        return saleEndDate;
    }

    function tokensale_open() public view returns (bool) {
        return saleIsActive;
    }

    function getAdmin() public view returns (address) {
        return admin;
    }

    function getTokenSold() public view returns (uint256) {
        return tokenSold;
    }

    function getTokenBatchName() public view returns (string memory) {
        return saleBatchName;
    }

    // Main functions start here
    function pause() public onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() public onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    function startSale(uint256 start, uint256 end, string memory _batchName) public onlyAdmin nonReentrant whenNotPaused {
        require(!saleIsActive, "Sale is already active.");
        require(
            !isDividendPaymentPeriodActive(),
            "Please wait until after dividend period."
        );
        require(start >= block.timestamp, "Invalid Start Date Input");
        require(end > start, "Invalid End Date Input");
        require(bytes(_batchName).length > 0, "Batch name must not be empty.");

        // Set Sales Dates ( saleEndDate - startTimestamp )
        saleEndDate = end;
        startTimestamp = start;
        saleBatchName = _batchName;

        // Reset Previous Data affected buy the Token Sale
        fundingReleased = false;
        saleIsActive = true;

        emit TokenSaleStarted(start, end);
    }

    function endSale() public onlyAdmin nonReentrant {
        require(saleIsActive, "Sale has already ended.");

        saleEndDate = 0;
        startTimestamp = 0;

        tokenSold = 0;
        saleIsActive = false;

        emit TokenSaleEnded(getTokenBatchName(), getTokenSold());
    }

    function buyTokens(uint256 usdcAmount_) public payable nonReentrant whenNotPaused {
        require(msg.sender != token.viewOwner(), "Token owner cannot purchase tokens.");

        require(tokensale_open() == true, "Token sale has ended");
        require(block.timestamp < saleEndDate, "Sale has ended.");
        require(
            token.totalSupply() + usdcAmount_ <= token.cap(),
            "Tokens has sold out."
        );

        bool hasCompletedKYC = token.isKYCed(msg.sender);

        require(hasCompletedKYC, "Only users the have completed the KYC process can purchase token");

        // address payable intermediateAddress = payable(address(this));

        if (msg.value <= 0) {
            _usdcInstance.transferFrom(msg.sender, address(this), usdcAmount_);
        }
        uint256 tokens = usdcAmount_.mul(token.rate());
        token.sendTokens(msg.sender, tokens);

        tokenSold += tokens;

        token.updateOwnsToken(msg.sender);

        emit TokensPurchased(_msgSender(), msg.sender, usdcAmount_, tokens);
    }

    function releaseFunds() public onlyAdmin nonReentrant {
        /// sales must end before Funds can be released to the _beneficiary
        require(tokensale_open() == false, "Token is still on sale.");
        require(fundingReleased == false, "Usdc has already being released.");

        uint256 usdcBalance = _usdcInstance.balanceOf(address(this));
        require(usdcBalance > 0, "You've not sold any tokens yet!");

        require(
            _usdcInstance.transfer(token.getBeneficiary(), usdcBalance),
            "sending USDC failed."
        );
        fundingReleased = true;
        emit FundsReleased(token.getBeneficiary(), token.cap());
    }
}
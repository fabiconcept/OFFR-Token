// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;
import "github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/access/AccessControl.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/utils/math/SafeMath.sol";
import "./math/SafeMathInt.sol";
import "./math/SafeMathUint.sol";
import "./uniswap/IUniswapV2Router02.sol";
import "./OfferToken.sol";

interface IUSDC {
    function balanceOf(address account) external view returns (uint256);

    function transfer(address recipient, uint256 amount)external returns (bool);

    function transferFrom(address sender, address recipient, uint256 amount
    ) external returns (bool);

    function transferBatch(
        address[] memory recipients,
        uint256[] memory amounts
    ) external returns (bool);

    function approve(address spender, uint256 amount) external returns (bool);

    function allowance(address owner, address spender)
        external
        view
        returns (uint256);
}

contract tokenHandler is AccessControl {
    OffrToken public token;
    using SafeMath for uint256;
    using SafeMathUint for uint256;
    using SafeMathInt for int256;

    address payable public admin;

    address internal constant UNISWAP_ROUTER_ADDRESS =
        0x7aa3103351aD2E508b8f91E7422F96b397075B3d;
    IUniswapV2Router02 public _uniswapRouter;
    address public _usdcToken = 0x152152799265e23BB8B307Ee05D874a221428ee8;
    IUSDC public _usdcInstance;

    bool isDividendPaymentPeriod = false;
    uint256 public dividendPeriod;
    uint256 public dividendInterval;
    uint256 public lastDividendTime;
    uint256 public dividendCount;
    mapping(address => uint256) public dividendReceived;
    uint256 public dividendPercent;

    mapping(address => uint256) private withdrawnAmounts;

    uint256 tokenSold = 0;

    uint256 public saleEndDate;
    bool public saleIsActive;
    bool public fundingReleased = false;
    uint256 public startTimestamp;

    event TokensPurchased(
        address indexed transmitter,
        address indexed buyer,
        uint256 amountUSDC,
        uint256 amountToken
    );

    event PaymentReceived(address indexed project_owner, uint256 amountUSDC);
    event FundsReleased(address indexed beneficiary, uint256 amountUSDC);
    event DividendDistributed(uint256 indexed count, uint256 amount);

    constructor(OffrToken _token) {
        admin = payable(msg.sender);
        token = _token;
        _usdcInstance = IUSDC(_usdcToken);
        lastDividendTime = block.timestamp;
        _uniswapRouter = IUniswapV2Router02(UNISWAP_ROUTER_ADDRESS);
    }

    modifier onlyAdmin() {
        require(msg.sender == admin, "Only the Owner can call this function");
        _;
    }

    function getDividendPeriod() public view returns (uint256) {
        return dividendPeriod;
    }

    function getDividendInterval() public view returns (uint256) {
        return dividendInterval;
    }

    function getLastDividendTime() public view returns (uint256) {
        return lastDividendTime;
    }

    function getDividendCount() public view returns (uint256) {
        return dividendCount;
    }

    function getName() public view returns (string memory) {
        return token.name();
    }

    function getDividendPercent() public view returns (uint256) {
        return dividendPercent;
    }

    function getSaleEndDate() public view returns (uint256) {
        return saleEndDate;
    }

    function getDividendIntervalCount() public view returns (uint256) {
        return dividendPeriod / dividendInterval;
    }

    function tokensale_open() public view returns (bool) {
        return saleIsActive;
    }

    function getAdmin() public view returns (address){
        return admin;
    }

    function getTokenSold() public view returns (uint256) {
        return tokenSold;
    }

    function setDividendPeriod(uint256 _period)
        public
        onlyAdmin
        returns (bool success)
    {
        require(
            tokensale_open() == true,
            "Change the Dividend Period while sales is ended"
        );
        dividendPeriod = _period;
        return true;
    }

    function setDividendInterval(uint256 _interval)
        public
        onlyAdmin
        returns (bool success)
    {
        require(
            tokensale_open() == true,
            "Change the Dividend payment period while sales is ended"
        );
        dividendInterval = _interval;
        return true;
    }

    function setDividendPercent(uint256 _value)
        public
        onlyAdmin
        returns (bool success)
    {
        require(tokensale_open() == true, "Sale is Active");

        uint256 dummy = 0;
        dividendPercent = dummy.add(_value).div(1000);
        return true;
    }

    function startSale(uint256 start, uint256 end) public onlyAdmin {
        require(!saleIsActive, "Sale is already active.");
        require(start >= block.timestamp, "Invalid Start Date Input");
        require(end > start, "Invalid End Date Input");

        // Set Sales Dates ( saleEndDate - startTimestamp )
        saleEndDate = end;
        startTimestamp = start;

        // Reset Previous Data affected buy the Token Sale
        lastDividendTime = block.timestamp;
        dividendCount = 0;
        isDividendPaymentPeriod = false;
        fundingReleased = false;
        saleIsActive = true;
    }

    function endSale() public onlyAdmin {
        require(saleIsActive, "Sale has already ended.");
        tokenSold = 0;
        saleIsActive = false;
    }

    function buyTokens(uint256 usdcAmount_) public payable {
        require(tokensale_open() == true, "Token sale has ended");
        require(block.timestamp < saleEndDate, "Sale has ended.");
        require(
            token.totalSupply() + usdcAmount_ <= token.cap(),
            "Sale has ended."
        );

        // address payable intermediateAddress = payable(address(this));

        if (msg.value <= 0) {
            _usdcInstance.transferFrom(msg.sender, address(this), usdcAmount_);
        }
        uint256 tokens = usdcAmount_.mul(token.rate());
        token.sendTokens(msg.sender, tokens);

        tokenSold += tokens;

        token.addHolder(msg.sender);

        emit TokensPurchased(_msgSender(), msg.sender, usdcAmount_, tokens);
    }

    function convertEthToUsdc(
        uint256 usdcAmount,
        address payable intermediateAddress
    ) public payable {
        uint256 deadline = block.timestamp + 15;
        address[] memory path = new address[](2);
        path[0] = _uniswapRouter.WETH();
        path[1] = _usdcToken;

        // Forward ETH to intermediate address (if specified)
        if (intermediateAddress != address(0)) {
            intermediateAddress.transfer(msg.value);
        }

        uint256[] memory amts = _uniswapRouter.swapETHForExactTokens{
            value: msg.value
        }(usdcAmount, path, address(this), deadline);
        require(amts[0] > 0, "Exchange failed.");

        // Refund leftover ETH back to user
        if (msg.value > amts[0]) {
            (bool success, ) = msg.sender.call{value: msg.value - amts[0]}("");
            require(success, "Refund failed.");
        }
    }

    function releaseFunds() public onlyAdmin {
        /// sales must end before Funds can be released to the _beneficiary
        require(tokensale_open() == false, "Token is still on sale.");
        require(fundingReleased == false, "Usdc has already being released.");
        
        uint256 usdcBalance = _usdcInstance.balanceOf(address(this));
        require(usdcBalance > 0, "You've not sold any tokens yet!");

        require(
            _usdcInstance.transfer(
                token.getBeneficiary(),
                token.cap().mul(token.rate())
            ),
            "sending USDC failed."
        );
        emit FundsReleased(token.getBeneficiary(), token.cap());
        fundingReleased = true;
    }

    function receivePayment(uint256 usdcAmount) public onlyAdmin {
        require(token.totalSupply() > 0, "total supply");
        // require();
        require(
            _usdcInstance.transferFrom(msg.sender, address(this), usdcAmount),
            "USDC Transfer not possible."
        );
        emit PaymentReceived(msg.sender, usdcAmount);
        startTimestamp = block.timestamp;
    }

    function distributeDividend() public onlyAdmin returns (bool success) {
        require(!tokensale_open(), "Token sales is still ongoing.");
        require(
            block.timestamp >= lastDividendTime.add(dividendInterval),
            "Not enough time has passed since the last dividend distribution."
        );

        uint256 totalDividendIntervalCount = getDividendIntervalCount();

        if (dividendCount < totalDividendIntervalCount) {
            uint256 contractUsdcBalance = _usdcInstance.balanceOf(
                address(this)
            );
            uint256 totalDividend = token.totalSupply().mul(500).div(10000);
            uint256 hasEnoughUsdc = contractUsdcBalance.mul(500).div(10000);

            require(
                totalDividend > 0,
                "Zero tokens has been bought at the moment."
            );
            require(hasEnoughUsdc > 0, "Contract does not have any USDC.");
            require(
                contractUsdcBalance >= totalDividend,
                "Contract does not have enough USDC."
            );

            uint256 totalDividendPaid = 0;
            uint256[] memory amounts = new uint256[](token.holderListLength());
            address[] memory recipients = new address[](
                token.holderListLength()
            );

            for (uint256 i = 0; i < token.holderListLength(); i++) {
                address[] memory listOfHolders = token.getHolderList();
                address holder = listOfHolders[i];
                uint256 balanceOfHolder = token.balanceOf(holder);
                uint256 dividendAmount = balanceOfHolder.mul(500).div(10000);
                if (dividendAmount > 0) {
                    recipients[i] = holder;
                    amounts[i] = dividendAmount;
                    dividendReceived[holder] = dividendReceived[holder].add(
                        dividendAmount
                    );
                    totalDividendPaid = totalDividendPaid.add(dividendAmount);
                }
            }

            require(
                totalDividendPaid <= contractUsdcBalance,
                "Contract does not have enough USDC to pay all holders."
            );

            _usdcInstance.transferBatch(recipients, amounts);
            emit DividendDistributed(dividendCount, totalDividend);
        } else {
            uint256 contractUsdcBalance = _usdcInstance.balanceOf(
                address(this)
            );
            uint256 totalDividend = token.totalSupply();
            uint256 hasEnoughUsdc = contractUsdcBalance;

            require(
                totalDividend > 0,
                "Zero tokens has been bought at the moment."
            );
            require(hasEnoughUsdc > 0, "Contract does not have any USDC.");
            require(
                contractUsdcBalance >= totalDividend,
                "Contract does not have enough USDC."
            );

            for (uint256 i = 0; i < token.holderListLength(); i++) {
                address[] memory listOfHolders = token.getHolderList();
                address holder = listOfHolders[i];
                uint256 balanceOfHolder = token.balanceOf(holder);
                if (balanceOfHolder > 0) {
                    dividendReceived[holder] = 0;
                    token.removeHolder(holder);
                    token.burn(holder, balanceOfHolder);
                }
            }

            _usdcInstance.transfer(msg.sender, contractUsdcBalance);
        }

        lastDividendTime = block.timestamp;
        dividendCount = dividendCount.add(1);
        return true;
    }

    function dividendReceivedAmountOf(address _owner)
        public
        view
        returns (uint256)
    {
        return dividendReceived[_owner];
    }
}

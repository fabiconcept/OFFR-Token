// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./token.sol";
import "./tokenSales.sol";

interface _USDC {
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

contract DividendManagement is AccessControl, Pausable, ReentrancyGuard {
    bytes32 private constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    OffrToken public token;
    TokenHandler public tokenSaleContract;
    using SafeMath for uint256;
    using SafeMathUint for uint256;
    using SafeMathInt for int256;

    address payable public admin;

    address internal constant UNISWAP_ROUTER_ADDRESS =
        0x7aa3103351aD2E508b8f91E7422F96b397075B3d;

    IUniswapV2Router02 public _uniswapRouter;

    // USDC token
    address private _usdcToken = 0xD3077255bE7183a690E2E1Af77581DC5303D3D04;
    _USDC public _usdcInstance;

    // Dividend Data
    uint256 private dividendPeriod;
    uint256 private dividendInterval;
    uint256 private lastDividendTime;
    uint256 private dividendCount;
    mapping(address => uint256) private dividendClaimed;
    mapping(address => uint256) private dividendsClaimedHistory;
    mapping(address => uint256) private lastTimeReceived;
    mapping(address => uint256) private unClaimdedDividends;
    uint256 private dividendPercent;

    // Events

    /**
     * @dev Event indicating that dividends have been paid to a project owner
     * @param project_owner The address of the project owner who distributed the dividends
     * @param amountUSDC The amount of dividends paid, in USDC
     */
    event DividendsDistributed(
        address indexed project_owner,
        uint256 amountUSDC
    );

    /**
     * @dev Event indicating that dividends have been claimed by a stakeholder
     * @param _stakeHolder The address of the stakeholder who claimed the dividends
     * @param amountClaimed The amount of dividends claimed
     */
    event DividendsClaimed(address indexed _stakeHolder, uint256 amountClaimed);

    /**
     * @dev Event indicating the start of a new dividend period
     * @param _period The number of the current dividend period
     * @param _interval The length of time between dividend periods
     * @param _percent The percentage of profits allocated to dividends for this period
     */
    event DividendPeriodStarted(
        uint256 _period,
        uint256 _interval,
        uint256 _percent
    );

    /**
     * @dev Event indicating the end of a dividend period
     */
    event DividendPeriodEnded();

    constructor(OffrToken _token, TokenHandler _tokenSaleContract) {
        admin = payable(msg.sender);
        token = _token;
        tokenSaleContract = _tokenSaleContract;
        _usdcInstance = _USDC(_usdcToken);
        _uniswapRouter = IUniswapV2Router02(UNISWAP_ROUTER_ADDRESS);
        _setupRole(PAUSER_ROLE, msg.sender);
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        lastDividendTime = block.timestamp;
    }

    /**
     * @dev Modifier that restricts function access to the contract owner, who is the distributor.
     * @notice This function can only be called by the contract owner.
     */
    modifier onlyDistributor() {
        require(
            msg.sender == admin,
            "Function can only be called by the distributor."
        );
        _;
    }

    /**
     * @dev Modifier that checks if the dividend payment period is currently active.
     * @notice This function can only be called by the contract owner during the dividend payment period.
     */
    // modifier onlyDuringDividendPaymentPeriod() {
    //     require(
    //         isDividendPaymentPeriodActive(),
    //         "Dividend payment period is not currently active."
    //     );
    //     _;
    // }

    // This function pauses the contract and can only be called by users with the PAUSER_ROLE.
    function pause() public onlyRole(PAUSER_ROLE) {
        _pause(); // calls the _pause function from the Pausable contract
    }

    // This function unpauses the contract and can only be called by users with the PAUSER_ROLE.
    function unpause() public onlyRole(PAUSER_ROLE) {
        _unpause(); // calls the _unpause function from the Pausable contract
    }

    // This function retrieves the dividend period value and returns it as a uint256.
    function getDividendPeriod() public view returns (uint256) {
        return dividendPeriod;
    }

    // This function retrieves the dividend interval value and returns it as a uint256.
    function getDividendInterval() public view returns (uint256) {
        return dividendInterval;
    }

    // This function checks whether the current dividend payment period is active and returns a boolean value.
    function isDividendPaymentPeriodActive() public view returns (bool) {
        return token.getDividendPaymentPeriodState(); // calls the getDividendPaymentPeriodState function from the token contract
    }

    // This function retrieves the timestamp of the last dividend payment and returns it as a uint256.
    function getLastDividendTime() public view returns (uint256) {
        return lastDividendTime;
    }

    // This function retrieves the timestamp of the last time dividends were received by a specific account and returns it as a uint256.
    function getLastTimeReceived(address account)
        public
        view
        returns (uint256)
    {
        return lastTimeReceived[account];
    }

    // This function retrieves the total number of dividend payments made and returns it as a uint256.
    function getTotalDividendCount() public view returns (uint256) {
        return dividendCount;
    }

    // This function retrieves the dividend percentage value and returns it as a uint256.
    function getDividendPercent() public view returns (uint256) {
        return dividendPercent;
    }

    // This function calculates the number of dividend intervals within the dividend period and returns it as a uint256.
    function getDividendIntervalCount() public view returns (uint256) {
        return dividendPeriod / dividendInterval; // calculates the number of dividend intervals by dividing the dividend period by the dividend interval
    }

    /**
     * @dev Starts a new dividend payment period, allocating a percentage of profits to dividends
     * @param _period The number of the current dividend period
     * @param _interval The length of time between dividend periods
     * @param _percent The percentage of profits allocated to dividends for this period
     */
    function startDividendPaymentPeriod(
        uint256 _period,
        uint256 _interval,
        uint256 _percent
    ) external onlyDistributor nonReentrant {
        // Ensure that tokens has been minted
        require(token.totalSupply() > 0, "No token has been sold yet");

        // Ensure that the Dividend Properties are properly set
        require(_percent > 0, "Dividend Percent can not be Zero (0).");
        require(_interval > 0, "Dividend Intervals can not be Zero (0).");
        require(_period > 0, "Dividend Period can not be Zero (0).");

        // Ensure that Token Sale is not active
        require(
            !tokenSaleContract.tokensale_open(),
            "Can not start Dividend period during an Active token sale."
        );

        // Set The Properties for the new Dividend Session
        dividendPeriod = _period;
        dividendInterval = _interval;
        dividendPercent = _percent;

        token.updateDividendPeriodStatus(true);

        emit DividendPeriodStarted(_period, _interval, _percent);
    }

    /**
     * @dev End the current dividend payment period
     */
    function endDividendPaymentPeriod() external onlyDistributor nonReentrant {
        require(
            isDividendPaymentPeriodActive(),
            "Dividend period isn't active"
        );
        require(
            getTotalDividendCount() > getDividendIntervalCount().sub(1),
            ""
        );

        address[] memory kycUsers = token.getKYCList();
        uint256 kycUsersListLength = token.kycUsersListLength();

        require(
            kycUsersListLength > 0,
            "KYC List must contain atleast on Stake Holder"
        );

        for (uint256 i = 0; i < kycUsersListLength; i++) {
            address stakeholder = kycUsers[i];
            uint256 stakeholderTokenBalance = token.balanceOf(stakeholder);
            uint256 _claimableDividends = claimableDividendsOf(stakeholder);

            if (_claimableDividends > 0) {
                unClaimdedDividends[stakeholder] = stakeholderTokenBalance.add(
                    _claimableDividends
                );
                dividendClaimed[stakeholder] = 0;
                token.burnMyBalance(stakeholder, stakeholderTokenBalance);
            }
        }

        dividendPeriod = 0;
        dividendInterval = 0;
        dividendPercent = 0;
        dividendCount = 0;
        lastDividendTime = block.timestamp;

        token.updateDividendPeriodStatus(false);

        emit DividendPeriodEnded();
    }

    /**
     * @dev Distributes dividends by funding the dividend Contract with USDC.
     *
     * Requirements:
     * - Tokens must have been sold or minted.
     * - The dividend payment period must be active.
     * - Not all dividend sessions have been paid.
     * - The required time has passed since the last dividend payment.
     * - Sufficient USDC funds are available to pay dividends.
     *
     * Emits a {DividendsDistributed} event indicating the amount of dividends distributed.
     *
     */
    function payDividends() external onlyDistributor nonReentrant {
        require(token.totalSupply() > 0, "No token has been sold or minted.");
        require(
            isDividendPaymentPeriodActive(),
            "Dividend payment period is not active."
        );
        require(
            getTotalDividendCount() < getDividendIntervalCount(),
            "All Dividend sessions has been paid"
        );
        require(
            block.timestamp > lastDividendTime.add(getDividendInterval()),
            string(
                abi.encodePacked(
                    "Dividends can only be paid once every ",
                    Strings.toString(getDividendInterval().div(86400)),
                    " days."
                )
            )
        );

        uint256 totalSupply = token.totalSupply();
        uint256 claimedAmount = 0;

        if (dividendCount < getDividendIntervalCount().sub(1)) {
            uint256 amountToFund = totalSupply.mul(dividendPercent).div(100000);
            claimedAmount = amountToFund;
            require(
                _usdcInstance.transferFrom(
                    msg.sender,
                    address(this),
                    amountToFund
                ),
                "USDC Failed to transfer to contract."
            );
        } else {
            uint256 amountToFund = totalSupply.mul(dividendPercent).div(100000);
            uint256 finalAmountToFund = amountToFund.add(totalSupply);

            require(
                _usdcInstance.transferFrom(
                    msg.sender,
                    address(this),
                    finalAmountToFund
                ),
                "USDC Failed to transfer to contract."
            );
            claimedAmount = amountToFund;
        }

        lastDividendTime = block.timestamp;
        dividendCount = dividendCount.add(1);

        emit DividendsDistributed(msg.sender, claimedAmount);
    }

    /**

    * @dev Claim dividends for a given account.
    *
    * Requirements:
    * - The account must not have already claimed dividends more than the total number of dividends paid so far.
    * - The account must have claimable dividends.
    * - If the account has not yet claimed dividends for getDividendIntervalCount() times, the dividends will be paid directly to the account's wallet.
    * - If the account has claimed dividends for getDividendIntervalCount() times, the dividends will be paid by adding the claimable dividends to the account's current token balance and the total will be paid in one transaction.
    * - Upon a successful dividend claim, the last time the account received a dividend will be updated, as well as the number of dividends claimed and unclaimed dividends. An event will also be emitted.
    *
    */
    function claimDividend() external nonReentrant whenNotPaused {
        uint256 _claimableDividends = claimableDividendsOf(msg.sender);

        require(
            _claimableDividends > 0,
            "You do not have any dividend to claim"
        );

        if (isDividendPaymentPeriodActive()) {
            if (dividendCount < getDividendIntervalCount()) {
                require(
                    _usdcInstance.transfer(msg.sender, _claimableDividends),
                    "USDC transfer failed."
                );
                dividendClaimed[msg.sender] = dividendClaimed[msg.sender].add(
                    _claimableDividends
                );
            } else {
                uint256 _stakeHolderTotalTokens = token.balanceOf(msg.sender);
                uint256 _amountToFund = _stakeHolderTotalTokens.add(
                    _claimableDividends
                );
                require(
                    _usdcInstance.balanceOf(address(this)) > _amountToFund,
                    "Contract does not has enough USDC to pay dividends"
                );

                require(
                    _usdcInstance.transfer(msg.sender, _amountToFund),
                    "USDC transfer failed."
                );

                token.burnMyBalance(msg.sender, _stakeHolderTotalTokens);
                dividendClaimed[msg.sender] = 0;
            }
        } else {
            require(
                unClaimdedDividends[msg.sender] > 0, 
                "You don't have any Unclaimed Dividends!"
            );
            require(
                _usdcInstance.transfer(msg.sender, _claimableDividends),
                "USDC transfer failed."
            );
            unClaimdedDividends[msg.sender] = 0;
        }

        lastTimeReceived[msg.sender] = block.timestamp;

        dividendsClaimedHistory[msg.sender] = dividendsClaimedHistory[
            msg.sender
        ].add(_claimableDividends);

        emit DividendsClaimed(msg.sender, _claimableDividends);
    }

    /**
     *
     * @dev Returns the amount of dividend claimable by a given stakeholder.
     * @param _stakeHolder Address of the stakeholder to check for claimable dividends.
     * @return claimableDividend The amount of claimable dividend.
     *
     */
    function claimableDividendsOf(address _stakeHolder)
        public
        view
        returns (uint256)
    {
        uint256 accumulatedDividends = accumulatedDividendsOf(_stakeHolder);
        uint256 claimedDividends = claimedDividendsOf(_stakeHolder);

        if (accumulatedDividends > 0) {
            return accumulatedDividends.sub(claimedDividends);
        } else {
            return 0;
        }
    }

    function claimedDividendsHistoryOf(address _stakeHolder)
        public
        view
        returns (uint256)
    {
        return dividendsClaimedHistory[_stakeHolder];
    }

    /**
     *
     * @dev Returns the amount of dividend already claimed by a given stakeholder.
     * @param _stakeHolder Address of the stakeholder to check for claimed dividends.
     * @return claimedDividend The amount of claimed dividend.
     *
     */
    function claimedDividendsOf(address _stakeHolder)
        internal
        view
        returns (uint256)
    {
        return dividendClaimed[_stakeHolder];
    }

    /**
     *
     * @dev Returns the amount of dividend accumulated by a given stakeholder.
     * @param _stakeHolder Address of the stakeholder to check for accumulated dividends.
     * @return accumulatedDividend The amount of accumulated dividend.
     *
     */
    function accumulatedDividendsOf(address _stakeHolder)
        public
        view
        returns (uint256)
    {
        uint256 leftOverDividends = getUnclaimedDividends(_stakeHolder);
        uint256 totalDividendSessions = getTotalDividendCount();
        uint256 stakeHolderBalance = token.balanceOf(_stakeHolder);
        uint256 dividendPerSession = stakeHolderBalance
            .mul(getDividendPercent())
            .div(100000);

        uint256 accumulatedDividends = dividendPerSession
            .mul(totalDividendSessions)
            .add(leftOverDividends);

        return accumulatedDividends;
    }

    /**
     *
     * @dev Returns the amount of unclaimed dividends of a given stakeholder.
     * @param _stakeHolder Address of the stakeholder to check for unclaimed dividends.
     * @return unclaimedDividend The amount of unclaimed dividend.
     *
     */
    function getUnclaimedDividends(address _stakeHolder)
        internal
        view
        returns (uint256)
    {
        return unClaimdedDividends[_stakeHolder];
    }

    /**
     *
     * @dev Returns the timestamp of the last dividend claim made by a given stakeholder.
     * @param _stakeHolder Address of the stakeholder to check for last dividend claim date.
     * @return lastClaimDate The timestamp of the last dividend claim.
     *
     */
    function lastClaimDateOf(address _stakeHolder)
        public
        view
        returns (uint256)
    {
        return lastTimeReceived[_stakeHolder];
    }
}

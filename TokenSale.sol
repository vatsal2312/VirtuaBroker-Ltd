// SPDX-License-Identifier: MIT
pragma solidity ^0.8.3;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";

contract TokenSale {
    event Bought(address from, uint256 amount);
    event WithDraw(uint256 amount, uint256 balance);
    event Transfer(address _from, uint256 amount, uint256 balance);

    IERC20 private _token;
    IUniswapV2Router02 private _uniswapRouter;
    address private _tokenPool;
    address private owner;
    uint256 public price;
    uint256 public fee;
    uint256 public bonus;
    uint256 public startSaleDate;
    uint256 public minTokensToBuy;
    uint256 public maxTokensToBuy;
    mapping(address => bool) public whitelistedTokens;
    mapping(address => bool) private _usdToken;

    address private _swapTokenReference;

    constructor(
        address tokenAddress,
        address tokenPool,
        address swapAddress,
        address swapTokenReference
    ) payable {
        _token = IERC20(tokenAddress);
        owner = msg.sender;
        _uniswapRouter = IUniswapV2Router02(swapAddress);
        _tokenPool = tokenPool;
        _swapTokenReference = swapTokenReference;
        price = 15; // 0,015 price is multiplied by 1000
        fee = 45; // 4.5% fee is multipliee by 10
        bonus = 0; // bonus is multipliee by 10
        startSaleDate = 0;
        minTokensToBuy = 0;
        maxTokensToBuy = 0;
        whitelistedTokens[0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c] = true;
        whitelistedTokens[0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56] = true;
        whitelistedTokens[0x55d398326f99059fF775485246999027B3197955] = true;
        _usdToken[0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56] = true;
        _usdToken[0x55d398326f99059fF775485246999027B3197955] = true;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Not Owner");
        _;
    }

    fallback() external payable {}

    receive() external payable {}

    function setTokenPool(address pool) public virtual onlyOwner {
        _tokenPool = pool;
    }

    function setFee(uint256 _fee) public virtual onlyOwner {
        fee = _fee;
    }

    function setPrice(uint256 _price) public virtual onlyOwner {
        price = _price;
    }

    function setBonus(uint256 _bonus) public virtual onlyOwner {
        bonus = _bonus;
    }

    function setStartSaleDate(uint256 _timeStart) public virtual onlyOwner {
        startSaleDate = _timeStart;
    }

    function setWhitelistedToken(address _tokenAdress, bool isAllowed)
        public
        virtual
        onlyOwner
    {
        whitelistedTokens[_tokenAdress] = isAllowed;
    }

    function setIsUsdToken(address _tokenAdress, bool isUsdt)
        public
        virtual
        onlyOwner
    {
        _usdToken[_tokenAdress] = isUsdt;
    }

    function setMinTokensToBuy(uint256 _minToBuy) public virtual onlyOwner {
        minTokensToBuy = _minToBuy;
    }

    function setMaxTokensToBuy(uint256 _maxToBuy) public virtual onlyOwner {
        maxTokensToBuy = _maxToBuy;
    }

    function buyTokensWithAnotherToken(address _tokenAddress, uint256 _amount)
        public
    {
        require(whitelistedTokens[_tokenAddress], "This token is not allowed");
        if (startSaleDate > 0) {
            require(
                startSaleDate <= block.timestamp,
                "The sale hasn't started yet"
            );
        }

        IERC20 coinToken = IERC20(_tokenAddress);

        require(_amount > 0, "You need to send amount > 0");
        require(
            coinToken.balanceOf(msg.sender) >= _amount,
            "There is not enough balance"
        );

        uint256 poolBalance = _token.balanceOf(_tokenPool);

        uint256 amountOfTokens = calculateAmountOfTokensWithAnotherToken(
            _tokenAddress,
            _amount
        );

        require(
            amountOfTokens <= poolBalance,
            "Not enough tokens in the reserve"
        );

        if (minTokensToBuy > 0) {
            require(
                amountOfTokens >= minTokensToBuy,
                "You need to buy more tokens"
            );
        }

        if (maxTokensToBuy > 0) {
            require(
                amountOfTokens <= maxTokensToBuy,
                "You need to buy less tokens"
            );
        }

        coinToken.transferFrom(msg.sender, address(this), _amount);

        _token.transferFrom(_tokenPool, msg.sender, amountOfTokens);
        emit Bought(msg.sender, amountOfTokens);
    }

    function buyTokens() public payable {
        if (startSaleDate > 0) {
            require(
                startSaleDate <= block.timestamp,
                "The sale hasn't started yet"
            );
        }

        uint256 amountTobuy = msg.value;
        uint256 poolBalance = _token.balanceOf(_tokenPool);

        require(amountTobuy > 0, "You need to send some ether or bnb");

        uint256 amountOfTokens = calculateAmountOfTokens(amountTobuy);

        require(
            amountOfTokens <= poolBalance,
            "Not enough tokens in the reserve"
        );

        if (minTokensToBuy > 0) {
            require(
                amountOfTokens >= minTokensToBuy,
                "You need to buy more tokens"
            );
        }

        if (maxTokensToBuy > 0) {
            require(
                amountOfTokens <= maxTokensToBuy,
                "You need to buy less tokens"
            );
        }

        // transfer token from contract wallet to sender wallet
        _token.transferFrom(_tokenPool, msg.sender, amountOfTokens);
        emit Bought(msg.sender, amountOfTokens);
    }

    function calculateAmountOfTokensWithAnotherToken(
        address _tokenAddress,
        uint256 _amount
    ) public view returns (uint256) {
        require(whitelistedTokens[_tokenAddress], "This token is not allowed");

        uint256 bonusAmount = (_amount * bonus) / 1000;
        uint256 amountAfterFee = _amount - ((_amount * fee) / 1000);

        if(_usdToken[_tokenAddress]) {
          return (amountAfterFee + bonusAmount) / (price * 1000000);
        }

        address[] memory path = new address[](2);

        path[0] = _tokenAddress;
        path[1] = _swapTokenReference;

        
        uint256[] memory amounts = _uniswapRouter.getAmountsOut(
            (amountAfterFee + bonusAmount),
            path
        );
        // 1 Token = 0.015 USD (BUSD);

        // Price of BUSD token and calculate amount of token
        // Mock data: 1 BNB = 414 BUSD (actually, the exchange rate always change)
        // 1 BNB = 414 / 0.015 = 27600 Tokens
        uint256 tokens = amounts[1] / (price * 1000000); // 9 decimals to convert because BUSD has 18 and WORKS 9, and 3 to make price 15 to 0,015
        return tokens;
    }

    function calculateAmountOfTokens(uint256 _amount)
        public
        view
        returns (uint256)
    {
        return
            calculateAmountOfTokensWithAnotherToken(
                0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c,
                _amount
            );
    }

    function calculateSwapTokensConversionWithAnotherToken(
        address _tokenAddress,
        uint256 _amount
    ) public view returns (uint256) {
        require(whitelistedTokens[_tokenAddress], "This token is not allowed");
        require(
            _amount >= 100000000000000,
            "You need to enter at least 0.00001"
        );

        if(_usdToken[_tokenAddress]) {
          return _amount;
        }

        address[] memory path = new address[](2);

        path[0] = _tokenAddress;
        path[1] = _swapTokenReference;

        uint256[] memory amounts = _uniswapRouter.getAmountsOut(_amount, path);

        return amounts[1];
    }

    function calculateSwapTokensConversion(uint256 _amount)
        public
        view
        returns (uint256)
    {
        return
            calculateSwapTokensConversionWithAnotherToken(
                0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c,
                _amount
            );
    }

    function getContractTokens() public view returns (uint256) {
        return _token.balanceOf(address(this));
    }

    function withDraw(uint256 _amount) public onlyOwner {
        require(_amount < contractBalance(), "Not enough BNB in the reserve");
        payable(owner).transfer(_amount);
        emit WithDraw(_amount, address(this).balance);
    }

    function withDrawToken(address _tokenAddress, uint256 _amount)
        public
        onlyOwner
    {
        require(whitelistedTokens[_tokenAddress], "This token is not allowed");
        require(
            _amount < contractTokenBalance(_tokenAddress),
            "Not enough BNB in the reserve"
        );
        IERC20(_tokenAddress).transfer(owner, _amount);
    }

    function transfer(address payable _to, uint256 _amount) public onlyOwner {
        require(_amount < contractBalance(), "Not enough BNB in the reserve");
        _to.transfer(_amount);
        emit Transfer(_to, _amount, address(this).balance);
    }

    function transferToken(
        address _tokenAddress,
        address payable _to,
        uint256 _amount
    ) public onlyOwner {
        require(whitelistedTokens[_tokenAddress], "This token is not allowed");
        require(
            _amount < contractTokenBalance(_tokenAddress),
            "Not enough in the reserve"
        );
        IERC20(_tokenAddress).transfer(_to, _amount);
    }

    function contractBalance() public view returns (uint256) {
        return address(this).balance;
    }

    function contractTokenBalance(address _tokenAddress)
        public
        view
        returns (uint256)
    {
        return IERC20(_tokenAddress).balanceOf(address(this));
    }

    function availableTokens() public view returns (uint256) {
        uint256 tokens = _token.balanceOf(_tokenPool);
        uint256 allowedToSell = _token.allowance(_tokenPool, address(this));
        if (tokens < allowedToSell) {
            return tokens;
        }
        return allowedToSell;
    }
}

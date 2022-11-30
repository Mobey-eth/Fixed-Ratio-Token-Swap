// SPDX-License-Identifier: MIT

/*
LEGEND -> a = dx = amount of token A in/out 
        a = dy = amount of token B in/out
        L(x) = total liquidity of A (reserve0)
        L(y) = total liquidity of B (reserve1)

        T(x) = total supply of shares of A
        T(y) = total supply of shares of B

        S(x) = shares of tokenA to mint
        S(y) = shares of tokenB to mint
*/
pragma solidity 0.8.17;
import "./IERC20.sol";

contract EkolanceFixedRatioSwap {
    IERC20 public immutable token0;
    IERC20 public immutable token1;

    uint256 public reserve0;
    uint256 public reserve1;

    uint256 public TotalSupplyA; // Total shares of tokenA
    uint256 public TotalSupplyB; // Total shares of tokenB

    mapping(address => uint256) public balanceOfA;
    mapping(address => uint256) public balanceOfB;

    uint256 public tokenAratio = 200;
    uint256 public tokenBratio = 50;

    mapping(address => bool) public isLP;

    error InsufficientBalance(uint256 actualBalance, uint256 withdrawBalance);

    event MintA(address indexed To, uint256 Shares);
    event MintB(address indexed To, uint256 Shares);

    event BurnA(address indexed From, uint256 Shares);
    event BurnB(address indexed From, uint256 Shares);
    event Swap(
        address indexed User,
        address TokenIn,
        uint256 amountIn,
        uint256 amountOut
    );
    event AddLiquidity(
        address indexed LP,
        uint256 amount0In,
        uint256 amount1In
    );
    event RemoveLiquidity(
        address indexed LP,
        uint256 amount0Out,
        uint256 amount1Out
    );

    constructor(address _token0, address _token1) {
        token0 = IERC20(_token0);
        token1 = IERC20(_token1);
    }

    function mintA(address _to, uint256 _amount) private {
        balanceOfA[_to] += _amount;
        TotalSupplyA += _amount;
        emit MintA(_to, _amount);
    }

    function mintB(address _to, uint256 _amount) private {
        balanceOfB[_to] += _amount;
        TotalSupplyB += _amount;
        emit MintB(_to, _amount);
    }

    function burnA(address _from, uint256 _amount) private {
        balanceOfA[_from] -= _amount;
        TotalSupplyA -= _amount;
        emit BurnA(_from, _amount);
    }

    function burnB(address _from, uint256 _amount) private {
        balanceOfB[_from] -= _amount;
        TotalSupplyB -= _amount;
        emit BurnB(_from, _amount);
    }

    // To aid user estimates (swapping from tokenA to tokenB)
    function getTokenAratio(uint256 _amount) public view returns (uint256) {
        return (_amount * tokenAratio) / 100;
    }

    // Also aids user estimates (swapping from tokenB to tokenA)
    function getTokenBratio(uint256 _amount) public view returns (uint256) {
        return (_amount * tokenBratio) / 100;
    }

    // Internal function to update token reserves in the contract.
    function _updateReserves(uint256 _res0, uint256 _res1) private {
        reserve0 = _res0;
        reserve1 = _res1;
    }

    function swap(address _tokenIn, uint256 _amountIn)
        external
        returns (uint256 amountOut)
    {
        require(_amountIn > 0, "Amount to swap cannot be Zero or less!");
        require(
            _tokenIn == address(token0) || _tokenIn == address(token1),
            "Unsupported token"
        );

        bool isToken0 = _tokenIn == address(token0);
        (
            IERC20 tokenIn,
            IERC20 tokenOut,
            uint256 resIn,
            uint256 resOut,
            uint256 tokenRatio
        ) = isToken0 // we initialise local variables.
                ? (token0, token1, reserve0, reserve1, tokenAratio)
                : (token1, token0, reserve1, reserve0, tokenBratio);

        // Transfer token in -- 1.2

        tokenIn.transferFrom(msg.sender, address(this), _amountIn);
        uint256 amountIn = tokenIn.balanceOf(address(this)) - resIn; // - to calculate amountIn

        /* 
            To calculate amount out (no fees included)
            from dx = 2dy || dy = 0.5dx ; hence,
            tokenA = 2tokenB || tokenB = 0.5tokenA
        */
        amountOut = (amountIn * tokenRatio) / 100;

        // update reserve state variables
        (uint256 res0, uint256 res1) = isToken0
            ? (resIn + amountIn, resOut - amountOut)
            : (resOut - amountOut, resIn + amountIn);

        _updateReserves(res0, res1);

        // Transfer token out
        tokenOut.transfer(msg.sender, amountOut);
        emit Swap(msg.sender, _tokenIn, amountIn, amountOut);
    }

    function addLiquidity(uint256 _amount0, uint256 _amount1)
        external
        returns (uint256 sharesA, uint256 sharesB)
    {
        require(
            _amount0 > 0 && _amount1 > 0,
            "Amounts provided cannot be Zero."
        );

        require(
            getTokenAratio(_amount0) == _amount1,
            "Token1 should be twice the amount of Token0"
        );
        token0.transferFrom(msg.sender, address(this), _amount0);
        token1.transferFrom(msg.sender, address(this), _amount1);

        uint256 bal0 = token0.balanceOf(address(this));
        uint256 bal1 = token1.balanceOf(address(this));

        uint256 amount0In = bal0 - reserve0; // - to calculate amountIn
        uint256 amount1In = bal1 - reserve1;

        /*
        To calculate shares to mint (for tokenA & tokenB respectively) --
            The increase in liquidity is directly proportional to the increase in the total
            shares, we have that;
                (L + a)/ L = (T + s) / T
                s = (a * T) / L --(Varies respective to x and y)
        */
        if (TotalSupplyA == 0 && TotalSupplyB == 0) {
            sharesA = amount0In;
            sharesB = amount1In;
            isLP[msg.sender] = true;
        } else {
            sharesA = (amount0In * TotalSupplyA) / reserve0;
            sharesB = (amount1In * TotalSupplyB) / reserve1;

            require(sharesA > 0 && sharesB > 0, "Shares cannot equal zero!");

            if (!isLP[msg.sender]) {
                isLP[msg.sender] = true;
            }
        }
        mintA(msg.sender, sharesA);
        mintB(msg.sender, sharesB);
        _updateReserves(bal0, bal1);

        emit AddLiquidity(msg.sender, amount0In, amount1In);
    }

    function removeLiquidity(uint256 _sharesA, uint256 _sharesB)
        external
        returns (uint256 amount0Out, uint256 amount1Out)
    {
        /*
        To calculate tokens to burn (for tokenA & tokenB respectively)-- 
            The amount of tokens withdrawn is directly proportional to the amount of
            shares, we have that;
                a / L = s / T

                a = (L * s ) / T --(Varies respective to x and y)

                dx = (reserve0 * sharesA) / Total shares A
                dy = (reserve1 * sharesB) / Total shares B
        */
        require(isLP[msg.sender], "Caller is not a liquidity provider!");

        require(
            _checkShares(_sharesA, _sharesB),
            "Caller is not a liquidity provider!"
        );

        amount0Out = (reserve0 * _sharesA) / TotalSupplyA;
        amount1Out = (reserve1 * _sharesB) / TotalSupplyB;
        isLP[msg.sender] = false;
        burnA(msg.sender, _sharesA);
        burnB(msg.sender, _sharesB);

        if (amount0Out > 0) {
            token0.transfer(msg.sender, amount0Out);
        }

        if (amount1Out > 0) {
            token1.transfer(msg.sender, amount1Out);
        }

        uint256 bal0 = token0.balanceOf(address(this));
        uint256 bal1 = token1.balanceOf(address(this));

        _updateReserves(bal0, bal1);
        emit RemoveLiquidity(msg.sender, amount0Out, amount1Out);
    }

    // Internal function to validate share balances
    function _checkShares(uint256 _sharesA, uint256 _sharesB)
        private
        view
        returns (bool)
    {
        require(
            _sharesA > 0 && _sharesB > 0,
            "Amounts of shares provided cannot be zero!"
        );
        uint256 lpBalA = balanceOfA[msg.sender];
        uint256 lpBalB = balanceOfB[msg.sender];

        if (_sharesA > lpBalA) {
            revert InsufficientBalance(lpBalA, _sharesA);
        }

        if (_sharesB > lpBalB) {
            revert InsufficientBalance(lpBalB, _sharesB);
        }

        return true;
    }

    // Public function to view shares of investors
    function getShares(address _liquidityProvider)
        public
        view
        returns (uint256 tokenAShares, uint256 tokenBShares)
    {
        tokenAShares = balanceOfA[_liquidityProvider];
        tokenBShares = balanceOfB[_liquidityProvider];
    }

    function getReserves()
        external
        view
        returns (
            uint112 reserve0Value,
            uint112 reserve1Value,
            uint32 blockTimestampLast
        )
    {
        blockTimestampLast = uint32(block.timestamp);
        reserve0Value = uint112(reserve0);
        reserve1Value = uint112(reserve1);
    }
}

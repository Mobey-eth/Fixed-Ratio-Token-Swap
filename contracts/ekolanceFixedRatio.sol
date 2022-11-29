// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;
import "./IERC20.sol";

contract CSAMM {
    IERC20 public immutable token0;
    IERC20 public immutable token1;

    uint256 public reserve0; // -- 1.1
    uint256 public reserve1;

    uint256 public tokenAratio = 200;
    uint256 public tokenBratio = 50;

    mapping(address => uint256) public AsupplyProvided;
    mapping(address => uint256) public BsupplyProvided;

    mapping(address => uint256) public Apercentage;
    mapping(address => uint256) public Bpercentage;
    mapping(address => bool) public isLP;

    address[] public liquidityProviders;

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

    function getTokenAratio(uint256 _amount) public view returns (uint256) {
        return (_amount * tokenAratio) / 100;
    }

    function getTokenBratio(uint256 _amount) public view returns (uint256) {
        return (_amount * tokenBratio) / 100;
    }

    function _updateReserves(uint256 _res0, uint256 _res1) private {
        reserve0 = _res0;
        reserve1 = _res1;
    }

    function swap(address _tokenIn, uint256 _amountIn)
        external
        returns (uint256 amountOut)
    {
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

        // calculate amount out, no fees included
        // tokenA = 2tokenB || tokenB = 0.5tokenA
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
        returns (uint256 tokenApercent, uint256 tokenBpercent)
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
         calculate percentages 
        */
        if (reserve0 == 0 && reserve1 == 0) {
            AsupplyProvided[msg.sender] += amount0In;
            BsupplyProvided[msg.sender] += amount1In;
            Apercentage[msg.sender] = 1000; // 100%
            Bpercentage[msg.sender] = 1000; // 100%
            isLP[msg.sender] = true;
            liquidityProviders.push(msg.sender);
            _updateReserves(bal0, bal1);
        } else {
            AsupplyProvided[msg.sender] += amount0In;
            BsupplyProvided[msg.sender] += amount1In;

            // Apercentage[msg.sender] = ( AsupplyProvided[msg.sender] * 1000 ) / bal0;
            // Bpercentage[msg.sender] = ( BsupplyProvided[msg.sender] * 1000 ) / bal1;
            if (!isLP[msg.sender]) {
                liquidityProviders.push(msg.sender);
            }
            _updateReserves(bal0, bal1);
            updatePercentages();
        }

        tokenApercent = Apercentage[msg.sender];
        tokenBpercent = Bpercentage[msg.sender];

        emit AddLiquidity(msg.sender, amount0In, amount1In);
    }

    function removeLiquidity()
        external
        returns (uint256 amount0Out, uint256 amount1Out)
    {
        /*
         To keep this demo and its implementation on the simpler side,
         a user can only remove 100% of the liquidity he adds. (but a user can still provide more liquidity
         if he's already done so in the past)
        */

        // amountout = (percentage * totalBal) / 1000;

        require(isLP[msg.sender], "Caller is not a liquidity provider!");
        amount0Out = (reserve0 * Apercentage[msg.sender]) / 1000;
        amount1Out = (reserve1 * Bpercentage[msg.sender]) / 1000;

        isLP[msg.sender] = false;

        _updateReserves(reserve0 - amount0Out, reserve1 - amount1Out);
        if (amount0Out > 0) {
            token0.transfer(msg.sender, amount0Out);
        }

        if (amount1Out > 0) {
            token1.transfer(msg.sender, amount1Out);
        }

        uint256 lpArrayLength = liquidityProviders.length;
        for (uint256 i; i < lpArrayLength; i++) {
            address _lp = liquidityProviders[i];
            if (_lp == msg.sender) {
                liquidityProviders[i] = liquidityProviders[
                    liquidityProviders.length - 1
                ];
                liquidityProviders.pop();
            }
        }
        updatePercentages();

        emit RemoveLiquidity(msg.sender, amount0Out, amount1Out);
    }

    function updatePercentages() private {
        // to calculate new percentages for everyone else
        for (uint256 i; i < liquidityProviders.length; ++i) {
            address _lp = liquidityProviders[i];
            Apercentage[_lp] = (AsupplyProvided[_lp] * 1000) / reserve0;
            Bpercentage[_lp] = (BsupplyProvided[_lp] * 1000) / reserve1;
        }
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

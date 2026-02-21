/**
 * Spdx-License-Identifier: UNLICENSED
 */
pragma solidity ^0.8.0;

import {OpynPricerInterface} from "./protocol-interfaces/OpynPricerInterface.sol";
import {OracleInterface} from "./protocol-interfaces/OracleInterface.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {IUniswapV3Factory} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {OracleLibrary} from "@uniswap/v3-periphery/contracts/libraries/OracleLibrary.sol";
import {TickMath} from "@uniswap/v3-core/contracts/libraries/TickMath.sol";
import {FullMath} from "@uniswap/v3-core/contracts/libraries/FullMath.sol";

contract UniswapV3OpynPricerAdapter is OpynPricerInterface {
    IUniswapV3Factory public immutable FACTORY;
    IUniswapV3Pool public immutable POOL;
    OracleInterface public immutable ORACLE;
    address public immutable UNDERLYING;
    address public immutable UNIT_OF_ACCOUNT;

    uint24[4] public FEES = [100, 500, 1000, 3000];

    constructor(
        address _underlying,
        address _unitOfAccount,
        address _factory,
        address _oracle
    ) {
        require(_underlying != address(0), "UniswapV3OpynPricerAdapter: zero underlying");
        require(_unitOfAccount != address(0), "UniswapV3OpynPricerAdapter: zero unitOfAccount");
        require(_factory != address(0), "UniswapV3OpynPricerAdapter: zero factory");
        require(_oracle != address(0), "UniswapV3OpynPricerAdapter: zero oracle");

        UNDERLYING = _underlying;
        UNIT_OF_ACCOUNT = _unitOfAccount;
        FACTORY = IUniswapV3Factory(_factory);
        ORACLE = OracleInterface(_oracle);

        // Find and set the pool
        POOL = IUniswapV3Pool(_findPool());
        require(address(POOL) != address(0), "UniswapV3OpynPricerAdapter: pool not found");
    }

    function getPrice() external view returns (uint256) {
        (uint160 sqrtPriceX96,,,,,,) = POOL.slot0();
        uint256 priceWad = _calculatePriceWad(sqrtPriceX96);
        return priceWad;
    }

    function _findPool() internal view returns (address pool) {
        // Sort tokens for getPool call (token0 < token1)
        address token0 = UNDERLYING < UNIT_OF_ACCOUNT ? UNDERLYING : UNIT_OF_ACCOUNT;
        address token1 = UNDERLYING < UNIT_OF_ACCOUNT ? UNIT_OF_ACCOUNT : UNDERLYING;

        for (uint256 i = 0; i < FEES.length; i++) {
            pool = FACTORY.getPool(token0, token1, FEES[i]);
            if (pool != address(0)) {
                return pool;
            }
        }
        return address(0);
    }

    function _calculatePriceWad(uint160 sqrtPriceX96) internal view returns (uint256 priceWad) {
        // Convert sqrtPriceX96 to price: price = (sqrtPriceX96)^2 / 2^192
        priceWad = FullMath.mulDiv(
            uint256(sqrtPriceX96),
            uint256(sqrtPriceX96),
            1 << 192
        ) * 1e18;

        // Adjust for token orientation
        if (POOL.token0() == UNIT_OF_ACCOUNT) {
            // price is UNIT_OF_ACCOUNT per UNDERLYING (correct orientation)
            return priceWad;
        } else {
            // invert: 1e36 / priceWad
            return 1e36 / priceWad;
        }
    }

    function getHistoricalPrice(uint80 _secondsAgo) external view returns (uint256, uint256) {
        require(_secondsAgo <= type(uint32).max, "UniswapV3OpynPricerAdapter: secondsAgo overflow");

        // Get TWAP tick from _secondsAgo seconds ago to now
        (int24 twapTick,) = OracleLibrary.consult(address(POOL), uint32(_secondsAgo));

        // Convert tick to sqrtPrice
        uint160 sqrtRatioX96 = TickMath.getSqrtRatioAtTick(twapTick);

        // Calculate price
        uint256 price = _calculatePriceWad(sqrtRatioX96);

        // Calculate timestamp
        uint256 timestamp = block.timestamp - uint32(_secondsAgo);

        return (price, timestamp);
    }

    function setExpiryPriceInOracle(uint256 _expiryTimestamp, uint80 _secondsAgo) external {
        require(_secondsAgo <= type(uint32).max, "UniswapV3OpynPricerAdapter: secondsAgo overflow");

        // Get historical price at expiry
        (int24 twapTick,) = OracleLibrary.consult(address(POOL), uint32(_secondsAgo));
        uint160 sqrtRatioX96 = TickMath.getSqrtRatioAtTick(twapTick);
        uint256 price = _calculatePriceWad(sqrtRatioX96);

        // Set expiry price in oracle
        ORACLE.setExpiryPrice(UNDERLYING, _expiryTimestamp, price);
    }
}
// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.14;

import "forge-std/Test.sol";
import "abdk-math/ABDKMath64x64.sol";

import "../src/interfaces/IUniswapV3Pool.sol";
import "../src/lib/FixedPoint96.sol";
import "../src/UniswapV3Pool.sol";

import "./ERC20Mintable.sol";

abstract contract TestUtils is Test {
    struct ExpectedStateAfterMint {
        UniswapV3Pool pool;
        ERC20Mintable token0;
        ERC20Mintable token1;
        uint256 amount0;
        uint256 amount1;
        int24 lowerTick;
        int24 upperTick;
        uint128 positionLiquidity;
        uint128 currentLiquidity;
        uint160 sqrtPriceX96;
        int24 tick;
    }

    struct ExpectedStateAfterSwap {
        UniswapV3Pool pool;
        ERC20Mintable token0;
        ERC20Mintable token1;
        uint256 userBalance0;
        uint256 userBalance1;
        uint256 poolBalance0;
        uint256 poolBalance1;
        uint160 sqrtPriceX96;
        int24 tick;
        uint128 currentLiquidity;
    }

    // ABDKMath64x64.sqrt takes Q64.64 numbers so we need to convert price to such number.
    // The price is expected to not have the fractional part, so we’re shifting it by 64 bits.
    // The sqrt function also returns a Q64.64 number but TickMath.getTickAtSqrtRatio takes a Q64.96 number
    // this is why we need to shift the result of the square root operation by 96 - 64 bits to the left
    function tick(uint256 price) internal pure returns (int24 tick_) {
        tick_ = TickMath.getTickAtSqrtRatio(
            uint160(
                int160(
                    ABDKMath64x64.sqrt(int128(int256(price << 64))) <<
                        (FixedPoint96.RESOLUTION - 64)
                )
            )
        );
    }

    function sqrtP(uint256 price) internal pure returns (uint160) {
        return TickMath.getSqrtRatioAtTick(tick(price));
    }

    function assertMintState(ExpectedStateAfterMint memory expected) internal {
        // check correct pool token balances
        assertEq(
            expected.token0.balanceOf(address(expected.pool)),
            expected.amount0,
            "incorrect token0 balance of pool"
        );
        assertEq(
            expected.token1.balanceOf(address(expected.pool)),
            expected.amount1,
            "incorrect token1 balance of pool"
        );

        // check position liquidity
        bytes32 positionKey = keccak256(
            abi.encodePacked(
                address(this),
                expected.lowerTick,
                expected.upperTick
            )
        );
        uint128 posLiquidity = expected.pool.positions(positionKey);
        assertEq(
            posLiquidity,
            expected.positionLiquidity,
            "incorrect position liquidity"
        );

        // check ticks liquidity
        (
            bool tickInitialized,
            uint128 tickLiquidityGross,
            int128 tickLiquidityNet
        ) = expected.pool.ticks(expected.lowerTick);
        assertTrue(tickInitialized);
        assertEq(
            tickLiquidityGross,
            expected.positionLiquidity,
            "incorrect lower tick gross liquidity"
        );
        assertEq(
            tickLiquidityNet,
            int128(expected.positionLiquidity),
            "incorrect lower tick net liquidity"
        );

        (tickInitialized, tickLiquidityGross, tickLiquidityNet) = expected
            .pool
            .ticks(expected.upperTick);
        assertTrue(tickInitialized);
        assertEq(
            tickLiquidityGross,
            expected.positionLiquidity,
            "incorrect upper tick gross liquidity"
        );
        assertEq(
            tickLiquidityNet,
            -int128(expected.positionLiquidity),
            "incorrect upper tick net liquidity"
        );

        // check tick is in bit map
        assertTrue(tickInBitMap(expected.pool, expected.lowerTick));
        assertTrue(tickInBitMap(expected.pool, expected.upperTick));

        // check current sqrtP, tick and liquidity
        (uint160 sqrtPriceX96, int24 currentTick) = expected.pool.slot0();
        assertEq(sqrtPriceX96, expected.sqrtPriceX96, "invalid current sqrtP");
        assertEq(currentTick, expected.tick, "invalid current tick");
        assertEq(
            expected.pool.liquidity(),
            expected.currentLiquidity,
            "invalid current liquidity"
        );
    }

    function assertSwapState(ExpectedStateAfterSwap memory expected) internal {
        // check user token balances
        assertEq(
            expected.token0.balanceOf(address(this)),
            uint256(expected.userBalance0),
            "invalid user ETH balance"
        );
        assertEq(
            expected.token1.balanceOf(address(this)),
            uint256(expected.userBalance1),
            "invalid user USDC balance"
        );

        // check pool token balances
        assertEq(
            expected.token0.balanceOf(address(expected.pool)),
            uint256(expected.poolBalance0),
            "invalid pool ETH balance"
        );
        assertEq(
            expected.token1.balanceOf(address(expected.pool)),
            uint256(expected.poolBalance1),
            "invalid pool USDC balance"
        );

        // check current sqrtP, tick and liquidity
        (uint160 sqrtPriceX96, int24 currentTick) = expected.pool.slot0();
        assertEq(sqrtPriceX96, expected.sqrtPriceX96, "invalid current sqrtP");
        assertEq(currentTick, expected.tick, "invalid current tick");
        assertEq(
            expected.pool.liquidity(),
            expected.currentLiquidity,
            "invalid current liquidity"
        );
    }

    function encodeSlippageCheckFailed(uint256 amount0, uint256 amount1)
        internal
        pure
        returns (bytes memory encoded)
    {
        encoded = abi.encodeWithSignature(
            "SlippageCheckFailed(uint256,uint256)",
            amount0,
            amount1
        );
    }

    function encodeError(string memory error)
        internal
        pure
        returns (bytes memory encoded)
    {
        encoded = abi.encodeWithSignature(error);
    }

    function encodeExtra(
        address _token0,
        address _token1,
        address payer
    ) internal pure returns (bytes memory) {
        return
            abi.encode(
                IUniswapV3Pool.CallbackData({
                    token0: _token0,
                    token1: _token1,
                    payer: payer
                })
            );
    }

    function tickInBitMap(UniswapV3Pool pool, int24 tick_)
        internal
        view
        returns (bool initialized)
    {
        int16 wordPos = int16(tick_ >> 8);
        uint8 bitPos = uint8(uint24(tick_ % 256));

        uint256 word = pool.tickBitmap(wordPos);

        initialized = (word & (1 << bitPos)) != 0;
    }
}

// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.24;
pragma abicoder v2;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./interfaces/ISwapRouter.sol";
import "./interfaces/IPool.sol";
import "./interfaces/IPoolManager.sol";

contract SwapRouter is ISwapRouter {
    IPoolManager public poolManager;

    constructor(address _poolManager) {
        poolManager = IPoolManager(_poolManager);
    }

    /// @dev Parses a revert reason that should contain the numeric quote
    function parseRevertReason(
        bytes memory reason
    ) private pure returns (uint256) {
        if (reason.length != 32) {
            if (reason.length < 68) revert("Unexpected error");
            assembly {
                reason := add(reason, 0x04)
            }
            revert(abi.decode(reason, (string)));
        }
        return abi.decode(reason, (uint256));
    }

    function exactInput(
        ExactInputParams calldata params
    ) external payable override returns (uint256 amountOut) {
        // 记录确定的输入 token 的 amount
        uint256 amountIn = params.amountIn;

        // 根据 tokenIn 和 tokenOut 的大小关系，确定是从 token0 到 token1 还是从 token1 到 token0
        bool zeroForOne = params.tokenIn < params.tokenOut;

        // 遍历指定的每一个 pool
        for (uint256 i = 0; i < params.indexPath.length; i++) {
            address poolAddress = poolManager.getPool(
                params.tokenIn,
                params.tokenOut,
                params.indexPath[i]
            );

            // 如果 pool 不存在，则抛出错误
            require(poolAddress != address(0), "Pool not found");

            // 获取 pool 实例
            IPool pool = IPool(poolAddress);

            // 构造 swap 函数需要的参数
            bytes memory data = abi.encode(
                msg.sender,
                params.tokenIn,
                params.tokenOut
            );

            // 调用 pool 的 swap 函数，进行交换，并拿到返回的 token0 和 token1 的数量
            (int256 amount0, int256 amount1) = pool.swap(
                params.recipient,
                zeroForOne,
                int256(amountIn),
                params.sqrtPriceLimitX96,
                data
            );

            // 更新 amountIn 和 amountOut
            amountIn = uint256(zeroForOne ? -amount0 : -amount1);
            amountOut += uint256(zeroForOne ? -amount1 : -amount0);

            // 如果 amountIn 为 0，表示交换完成，跳出循环
            if (amountIn == 0) {
                break;
            }
        }

        // 如果交换到的 amountOut 小于指定的最少数量 amountOutMinimum，则抛出错误
        require(amountOut >= params.amountOutMinimum, "Slippage exceeded");

        // 发射 Swap 事件
        emit Swap(msg.sender, zeroForOne, params.amountIn, amountIn, amountOut);

        // 返回 amountOut
        return amountOut;
    }

    function exactOutput(
        ExactOutputParams calldata params
    ) external payable override returns (uint256 amountIn) {
        // 记录确定的输出 token 的 amount
        uint256 amountOut = params.amountOut;

        // 根据 tokenIn 和 tokenOut 的大小关系，确定是从 token0 到 token1 还是从 token1 到 token0
        bool zeroForOne = params.tokenIn < params.tokenOut;

        // 遍历指定的每一个 pool
        for (uint256 i = 0; i < params.indexPath.length; i++) {
            address poolAddress = poolManager.getPool(
                params.tokenIn,
                params.tokenOut,
                params.indexPath[i]
            );

            // 如果 pool 不存在，则抛出错误
            require(poolAddress != address(0), "Pool not found");

            // 获取 pool 实例
            IPool pool = IPool(poolAddress);

            // 构造 swap 函数需要的参数
            bytes memory data = abi.encode(
                msg.sender,
                params.tokenIn,
                params.tokenOut
            );

            // 调用 pool 的 swap 函数，进行交换，并拿到返回的 token0 和 token1 的数量
            (int256 amount0, int256 amount1) = pool.swap(
                msg.sender,
                zeroForOne,
                -int256(amountOut),
                params.sqrtPriceLimitX96,
                data
            );

            // 更新 amountOut 和 amountIn
            amountOut = uint256(zeroForOne ? -amount1 : -amount0);
            amountIn += uint256(zeroForOne ? -amount0 : -amount1);

            // 如果 amountOut 为 0，表示交换完成，跳出循环
            if (amountOut == 0) {
                break;
            }
        }

        // 如果交换到指定数量 tokenOut 消耗的 tokenIn 数量超过指定的最大值，报错
        require(amountIn <= params.amountInMaximum, "Slippage exceeded");

        // 发射 Swap 事件
        emit Swap(
            msg.sender,
            zeroForOne,
            params.amountOut,
            amountOut,
            amountIn
        );

        // 返回交换后的 amountIn
        return amountIn;
    }

    // 报价，指定 tokenIn 的数量和 tokenOut 的最小值，返回 tokenOut 的实际数量
    function quoteExactInput(
        QuoteExactInputParams calldata params
    ) external override returns (uint256 amountOut) {
        // 因为没有实际 approve，所以这里交易会报错，我们捕获错误信息，解析需要多少 token
        try
            this.exactInput(
                ExactInputParams({
                    tokenIn: params.tokenIn,
                    tokenOut: params.tokenOut,
                    indexPath: params.indexPath,
                    recipient: msg.sender,
                    deadline: block.timestamp + 1 hours,
                    amountIn: params.amountIn,
                    amountOutMinimum: 0,
                    sqrtPriceLimitX96: params.sqrtPriceLimitX96
                })
            )
        {} catch (bytes memory reason) {
            return parseRevertReason(reason);
        }
    }

    // 报价，指定 tokenOut 的数量和 tokenIn 的最大值，返回 tokenIn 的实际数量
    function quoteExactOutput(
        QuoteExactOutputParams calldata params
    ) external override returns (uint256 amountIn) {
        try
            this.exactOutput(
                ExactOutputParams({
                    tokenIn: params.tokenIn,
                    tokenOut: params.tokenOut,
                    indexPath: params.indexPath,
                    recipient: msg.sender,
                    deadline: block.timestamp + 1 hours,
                    amountOut: params.amountOut,
                    amountInMaximum: type(uint256).max,
                    sqrtPriceLimitX96: params.sqrtPriceLimitX96
                })
            )
        {} catch (bytes memory reason) {
            return parseRevertReason(reason);
        }
    }

    function swapCallback(
        int256 amount0Delta,
        int256 amount1Delta,
        bytes calldata data
    ) external override {
        // transfer token
        (address payer, address token0, address token1) = abi.decode(
            data,
            (address, address, address)
        );
        if (amount0Delta > 0) {
            IERC20(token0).transfer(payer, uint(amount0Delta));
        }
        if (amount1Delta > 0) {
            IERC20(token1).transfer(payer, uint(amount1Delta));
        }
    }
}

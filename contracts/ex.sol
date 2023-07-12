// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import './token.sol';
import "hardhat/console.sol";

contract TokenExchange is Ownable {
    string public exchange_name = '';

    address tokenAddr;                                  // TODO: paste token contract address here
    Token public token = Token(tokenAddr);                                

    // Liquidity pool for the exchange
    uint private token_reserves = 0;
    uint private eth_reserves = 0;

    mapping(address => uint) private lps; 
     
    // Needed for looping through the keys of the lps mapping
    address[] private lp_providers;                     

    // liquidity rewards
    uint private swap_fee_numerator = 3;                
    uint private swap_fee_denominator = 100;

    // Constant: x * y = k
    uint private k;

    constructor() {}
    
    // Function createPool: Initializes a liquidity pool between your Token and ETH.
    // ETH will be sent to pool in this transaction as msg.value
    // amountTokens specifies the amount of tokens to transfer from the liquidity provider.
    // Sets up the initial exchange rate for the pool by setting amount of token and amount of ETH.
    function createPool(uint amountTokens)
        external
        payable
        onlyOwner
    {
        // This function is already implemented for you; no changes needed.
        require(token_reserves == 0, "Token reserves was not 0");
        require(eth_reserves == 0, "ETH reserves was not 0.");

        require(msg.value > 0, "Need eth to create pool.");
        uint tokenSupply = token.balanceOf(msg.sender);
        require(amountTokens <= tokenSupply, "Not enough tokens to create the pool");
        require(amountTokens > 0, "Need tokens to create pool.");

        token.transferFrom(msg.sender, address(this), amountTokens);
        token_reserves = token.balanceOf(address(this));
        eth_reserves = msg.value;
        k = token_reserves * eth_reserves;
    }

    // Function removeLP: removes a liquidity provider from the list.
    // This function also removes the gap left over from simply running "delete".
    function removeLP(uint index) private {
        require(index < lp_providers.length, "Specified index is larger than the number of lps");
        lp_providers[index] = lp_providers[lp_providers.length - 1];
        lp_providers.pop();
    }

    // Function getSwapFee: Returns the current swap fee ratio to the client.
    function getSwapFee() public view returns (uint, uint) {
        return (swap_fee_numerator, swap_fee_denominator);
    }

    /* ========================= Liquidity Provider Functions =========================  */ 

    // Function addLiquidity: Adds liquidity given a supply of ETH (sent to the contract as msg.value).
    // You can change the inputs, or the scope of your function, as needed.
    function addLiquidity(uint max_exchange_rate, uint min_exchange_rate) 
        external 
        payable
    {
        require(msg.value > 0, "No ETH sent with the transaction.");
        uint tokenAmount = (msg.value * token_reserves) / eth_reserves;
        require(tokenAmount > 0, "Cannot add 0 tokens.");

        uint exchangeRate = (tokenAmount * 1e18) / msg.value;
        require(exchangeRate >= min_exchange_rate, "Exchange rate below minimum.");

        token.transferFrom(msg.sender, address(this), tokenAmount);
        token_reserves += tokenAmount;
        eth_reserves += msg.value;
        k = token_reserves * eth_reserves;
        lps[msg.sender] += tokenAmount;
        lp_providers.push(msg.sender);
    }


    // Function removeLiquidity: Removes liquidity given the desired amount of ETH to remove.
    // You can change the inputs, or the scope of your function, as needed.
    function removeLiquidity(uint amountETH, uint max_exchange_rate, uint min_exchange_rate)
        public 
        payable
    {
        require(amountETH > 0, "Cannot remove 0 ETH.");
        require(lps[msg.sender] > 0, "No liquidity provided by this address.");

        uint tokenAmount = (amountETH * token_reserves) / eth_reserves;
        require(tokenAmount > 0, "Cannot remove 0 tokens.");

        uint exchangeRate = (tokenAmount * 1e18) / amountETH;
        require(exchangeRate >= min_exchange_rate, "Exchange rate below minimum.");

        uint lpTokenAmount = lps[msg.sender];
        require(lpTokenAmount >= tokenAmount, "Insufficient liquidity provided.");

        token.transfer(msg.sender, tokenAmount);
        token_reserves -= tokenAmount;
        eth_reserves -= amountETH;
        k = token_reserves * eth_reserves;
        lps[msg.sender] -= tokenAmount;

        if (lps[msg.sender] == 0) {
            uint index = lp_providers.length;
            for (uint i = 0; i < lp_providers.length; i++) {
                if (lp_providers[i] == msg.sender) {
                    index = i;
                    break;
                }
            }
            if (index < lp_providers.length) {
                removeLP(index);
            }
        }

        payable(msg.sender).transfer(amountETH);
    }

    // Function removeAllLiquidity: Removes all liquidity that msg.sender is entitled to withdraw
    // You can change the inputs, or the scope of your function, as needed.
    function removeAllLiquidity(uint max_exchange_rate, uint min_exchange_rate)
        external
        payable
    {
        uint lpTokenAmount = lps[msg.sender];
        removeLiquidity(lpTokenAmount, max_exchange_rate, min_exchange_rate);
    }

    /***  Define additional functions for liquidity fees here as needed ***/


    /* ========================= Swap Functions =========================  */ 

    // Function swapTokensForETH: Swaps your token with ETH
    // You can change the inputs, or the scope of your function, as needed.
    function swapTokensForETH(uint amountTokens, uint max_exchange_rate)
        external 
        payable
    {
        require(amountTokens > 0, "Cannot swap 0 tokens.");
        require(lps[msg.sender] >= amountTokens, "Insufficient liquidity provided.");

        uint ethAmount = (amountTokens * eth_reserves) / token_reserves;
        require(ethAmount > 0, "Cannot receive 0 ETH.");

        uint exchangeRate = (amountTokens * 1e18) / ethAmount;
        require(exchangeRate <= max_exchange_rate, "Exchange rate above maximum.");

        token.transferFrom(msg.sender, address(this), amountTokens);
        token_reserves += amountTokens;
        eth_reserves -= ethAmount;
        k = token_reserves * eth_reserves;
        lps[msg.sender] -= amountTokens;

        payable(msg.sender).transfer(ethAmount);
    }

    // Function swapETHForTokens: Swaps ETH for your tokens
    // ETH is sent to contract as msg.value
    // You can change the inputs, or the scope of your function, as needed.
    function swapETHForTokens(uint max_exchange_rate)
        external
        payable 
    {
        require(msg.value > 0, "No ETH sent with the transaction.");
        
        uint tokenAmount = (msg.value * token_reserves) / eth_reserves;
        require(tokenAmount > 0, "Cannot receive 0 tokens.");

        uint exchangeRate = (tokenAmount * 1e18) / msg.value;
        require(exchangeRate <= max_exchange_rate, "Exchange rate above maximum.");

        token.transfer(msg.sender, tokenAmount);
        token_reserves -= tokenAmount;
        eth_reserves += msg.value;
        k = token_reserves * eth_reserves;

        lps[msg.sender] += tokenAmount;
        lp_providers.push(msg.sender);
    }
}

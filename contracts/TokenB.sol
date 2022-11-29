// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract Group2CoinB is ERC20 {
    uint256 public initialAmount;
    address public owner;

    constructor(uint256 _amount) ERC20("Group2CoinB", "GRP2B") {
        owner = msg.sender;
        initialAmount = _amount;
        _mint(msg.sender, initialAmount);
    }

    function mintMore() public {
        // For testing purposes, anyone can mint 1000 tokens.
        _mint(msg.sender, 1000e18);
    }
}

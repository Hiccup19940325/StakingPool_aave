// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.6.12;

import {ERC20} from "@aave/protocol-v2/contracts/dependencies/openzeppelin/contracts/ERC20.sol";
import {Ownable} from "@aave/protocol-v2/contracts/dependencies/openzeppelin/contracts/Ownable.sol";

contract MockToken is ERC20, Ownable {
    constructor() public ERC20("RewardToken", "RT") {}

    function mint(address user, uint amount) public {
        _mint(user, amount);
    }
}

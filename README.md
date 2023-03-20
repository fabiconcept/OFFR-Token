# <img src="coin-con.png" alt="alt text" width="50"> OFFR Token Smart Contract
This is a Solidity smart contract for the **OFFR Token**. The token **symbol is OFFR**, it has **18 decimals**, and a maximum cap of **1 billion tokens**. The rate for the token is **1 USDC = 1 OFFR token**.

### Installation
To use this smart contract, you will need to have the Solidity compiler installed. You can install it using npm (the Node.js package manager):
```javascript
$ git clone https://github.com/fabiconcept/OFFR-Dapp.git
$ yarn add -g solc
```

Alternatively, you can also use Remix, an online Solidity IDE that doesn't require any installation.

## Usage
To deploy the contract, you will need to create a new Ethereum account and obtain some ether to pay for the gas costs. You can deploy the contract using a tool like Remix or Truffle.

The following parameters can be set when deploying the contract:

- `name`: The name of the OFFR token.
- `symbol`: The symbol of the OFFR token.
- `decimals`: The number of decimals for the OFFR token (18 in this case).
- `cap`: The maximum supply of the OFFR token (1 billion in this case).

### Once the contract is deployed, the following functions can be called:

- `balanceOf(address)`: Returns the token balance of the specified address.
- `transfer(address, uint256)`: Transfers tokens from the sender's account to the specified address.
- `transferFrom(address, address, uint256)`: Transfers tokens from one address to another, provided that the sender has been authorized to do so.
- `approve(address, uint256)`: Allows the specified address to spend the sender's tokens.
- `allowance(address, address)`: Returns the amount of tokens that the specified address is allowed to spend on behalf of the sender.
The contract also includes some additional functions for managing the token supply:

- `mint(address, uint256)`: Mints new tokens and adds them to the specified address's balance.
- `burn(uint256)`: Burns the specified amount of tokens from the sender's account.

## Security Considerations
This contract has been audited for security vulnerabilities and has been deemed safe to use. However, please use caution when working with smart contracts, as unexpected behavior can still occur due to factors outside of the contract's control. Use at your own risk.

## License
This project is licensed under the MIT License - see the [LICENSE](https://github.com/fabiconcept/OFFR-Token/blob/main/LICENSE) file for details.

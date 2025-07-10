require("@nomiclabs/hardhat-waffle");
require('@nomiclabs/hardhat-etherscan');
require('@openzeppelin/hardhat-upgrades');
require('dotenv').config();
require("@nomiclabs/hardhat-ethers");

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  solidity: {
    version: "0.8.20",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200,
      },
      viaIR: true,
    },
  },
  // solidity: "0.8.19",
   networks: {
      hardhat: {},
      testnet: {
        allowUnlimitedContractSize: true,
       url: "https://rpc.bimtvi.com",
       accounts: [`0x${process.env.PRIVATE_KEY}`],
       gas: 2100000,
        gasPrice: 8000000000
     },
      mumbai: {
         allowUnlimitedContractSize: true,
        url: "https://polygon-mumbai.infura.io/v3/",
        accounts: [`0x${process.env.PRIVATE_KEY}`],
        gas: 2100000,
        gasPrice: 8000000000
      },
      vanar: {
        url: "https://rpc.vanarchain.com",
        chainId: 2040,
        accounts: [`0x${process.env.PRIVATE_KEY}`],
        gas: 5000000
      },
      sepolia: {
        url: "https://sepolia.infura.io/v3/",
        chainId: 11155111,
        accounts: [`0x${process.env.PRIVATE_KEY}`],
        gas: 5000000
      },
      ethereum: {
        url: "https://mainnet.infura.io/v3/",
        chainId: 1,
        accounts: [`0x${process.env.PRIVATE_KEY}`],
        gas: 5000000
      },
      vanguard: {
        url: "https://rpc-vanguard.vanarchain.com",
        chainId: 78600,
        accounts: [`0x${process.env.PRIVATE_KEY}`],
        gas: 5000000
      },
      testnet: {
        url: "https://rpc.bimtvi.com",
        chainId: 1947,
        accounts: [`0x${process.env.PRIVATE_KEY}`],
        gas: 5000000
      }
   },
   etherscan: {
    
    apiKey: ""

  },
  polygonscan:{
    apiKey: ""
  },
  sourcify: {
    // Disabled by default
    // Doesn't need an API key
    enabled: true
  }
};

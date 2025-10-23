#JILAI Token Sale

    This project is a smart contract-based token sale platform for the JILAI Token. It allows users to purchase tokens using USDT and implements key features such as whitelisting, KYC verification, and early-bird bonuses.

#Requirements

    Node.js
    npm
    Hardhat
    OpenZeppelin
    Installation

#Install dependencies:

npm install

Set up a .env file with your wallet credentials and network settings.

#Deploying Contracts:

    Set the JILAI Token and USDT contract addresses in the deploy.js script:

const jilaiTokenAddress = "0xYourJilaiTokenAddress"; const USDTAddress = "0xYourUSDTAddress";

Run the deployment script:

npx hardhat run scripts/deploy.js --network

#Usage:

Once deployed, the Token Sale contract allows users to:

    Purchase JILAI tokens using USDT
    Participate in bonus schemes based on purchase timing.

#License:

    This project is licensed under the MIT License.


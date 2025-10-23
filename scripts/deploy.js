const {ethers, upgrades} = require("hardhat");

async function main(){

    const duration = {
    seconds: function (val) { return val; },
    minutes: function (val) { return val * this.seconds(60); },
    hours: function (val) { return val * this.minutes(60); },
    days: function (val) { return val * this.hours(24); },
    weeks: function (val) { return val * this.days(7); },
    years: function (val) { return val * this.days(365); },
    };

    // Dev comments - For development closing time is set to 30 days
  const latestTime = Math.floor(new Date().getTime() / 1000);
  const _openingTime = latestTime + duration.minutes(4);
  const _closingTime = _openingTime + duration.days(90);


    //Deployer Address
    const [deployer] = await ethers.getSigners();
    console.log(" Deploying with account:", deployer.address);

    // // // //Deploying JILAI TOKEN
    // const JilaiToken = await ethers.getContractFactory("JilaiToken");
    // const jilaiToken = await upgrades.deployProxy(JilaiToken,[ethers.parseUnits("2000000000", 18)], {
    //     initializer: "initialize",
    //     kind: "uups"
    // });
    // JilaiTokenAddress = await jilaiToken.getAddress();
    // console.log("JILAI Token deployed to:", JilaiTokenAddress)

    //Deploy JilaiAirdrop
    // const JilaiAirdrop = await ethers.getContractFactory("JilaiAirdrop");
    // const jilaiAirdrop = await upgrades.deployProxy(JilaiAirdrop, [], {
    //     initializer: "initialize",
    //     kind: "uups"
    // });
    // const JilaiAirdropAddress = await jilaiAirdrop.getAddress();
    // console.log("JilaiAirdrop deployed to:", JilaiAirdropAddress);

    // const JilaiTokenAddress="0xfF449Ae38fdcDcc84Bdf88f70cBDC62ACfefc29F";
    // // // //  //Deploy TOKEN VESTING
    //  const JilaiVesting = await ethers.getContractFactory("JilaiVesting");
    //  const JilaiVesting_ = await upgrades.deployProxy(JilaiVesting, [JilaiTokenAddress], {
    //      initializer: "initialize",
    //      kind: "uups"
    //  });
    //  const JilaiVestingAddress = await JilaiVesting_.getAddress();
    //  console.log("JilaiVesting Deployed to:",JilaiVestingAddress);


    // const JilaiVestingAddress = "0x05E8ad14C2aa643A38b21500d3c97c5246f2d097";

   
    const JilaiTokenAddress = "0xfF449Ae38fdcDcc84Bdf88f70cBDC62ACfefc29F";
    const VestingContractAddress = "0x31b37226296862080F92d2b162d2A3b1D581654f";
    const PriceFeedAddress = "0x694AA1769357215DE4FAC081bf1f309aDC325306"; // Example ETH/USD Sepolia

    const YourContract = await ethers.getContractFactory("JilaiCrowdSale"); // replace with actual contract name
    const contractProxy = await upgrades.deployProxy(
        YourContract,
        [JilaiTokenAddress, VestingContractAddress, PriceFeedAddress], // initializer args
        {
            initializer: "initialize",
            kind: "uups",
        }
    );

    const _Crowdsale=await contractProxy.getAddress();
    console.log("Contract Proxy deployed at:", _Crowdsale);



 }

main().catch((error) => {
    console.error(error);
    process.exit(1);
})

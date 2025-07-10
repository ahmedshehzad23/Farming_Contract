async function main() {
    const DLPFarming = await ethers.getContractFactory("DLPFarming");
    console.log("Deploying DLP, ProxyAdmin, and then Proxy...");

    // Deploy ProxyAdmin
    // const proxyAdmin = await upgrades.deployProxyAdmin();
    // console.log("ProxyAdmin deployed to:", proxyAdmin.address);


    let status = true //true for Vanar deployment and false for Ethereum
    
    // Deploy Exchange proxy with ProxyAdmin
    const proxy = await upgrades.deployProxy(DLPFarming, ["DLPFarming","0x0000000000000000000000000000000000000000","DLP Token Address Here",status], { initializer: 'initialize' });
    console.log("Proxy of DLP deployed to:", proxy.address);

}

main()
    .then(() => process.exit(0))
    .catch(error => {
        console.error(error);
        process.exit(1);
    });
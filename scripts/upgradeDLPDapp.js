async function main() {
    const BoxV2 = await ethers.getContractFactory("DLPFarming")
    let box = await upgrades.upgradeProxy("0xd4e1e7409807E9d02E2fED55924BE730b27c2554", BoxV2)
    console.log("Your upgraded proxy is done!", box.address)
}

main()
    .then(() => process.exit(0))
    .catch(error => {
        console.error(error)
        process.exit(1)
    })
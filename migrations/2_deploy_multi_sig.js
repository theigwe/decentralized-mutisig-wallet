const MultiSig = artifacts.require('MultiSig')

module.exports = (deployer, network) => {
  console.log(`Deploying contracts with network: ${network}`);

  deployer.deploy(MultiSig)
    .then(async () => {
      const multiSig = await MultiSig.deployed();
      console.log('MutltiSig deployed at:', multiSig.address);
    })
    .catch(console.error);
}
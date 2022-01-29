const { expect, assert } = require("chai");
const { ethers } = require("hardhat");

describe("Registar", () => {
  let registrar;
  const overGas = 29000000;
  const underGas = 20000000;

  let accounts = [];

  before(async () => {
    accounts = await ethers.getSigners();
    const Registrar = await ethers.getContractFactory("Registrar");
    registrar = await Registrar.deploy();
    console.log("Registrar Deployed To: ", registrar.address);
  });

  describe("Locking...", () => {
    it("Should lock a name for 5 minutes", async () => {
      expect(await registrar.lock("Hello Name", { gasLimit: underGas })).to.emit(registrar, "Locked");
    });

    it("Should not lock a name if gas too high", async () => {
      try {
        await registrar.lock("Hello Name", { gasLimit: overGas });
      } catch (err) {
        assert(err.toString().indexOf("Gas too high. Front-running not allowed") > 0);
      }
    });

    it("Should not lock a name twice", async () => {
      try {
        await registrar.lock("Hello Name", { gasLimit: underGas });
      } catch (err) {
        assert(err.toString().indexOf("Can not lock. Front-running not allowed") > 0);
      }
    });

    it("Should not lock an already locked name with another user", async () => {
      try {
        const reg2 = await registrar.connect(accounts[2]);
        await reg2.lock("Hello Name", { gasLimit: underGas });
      } catch (err) {
        assert(err.toString().indexOf("Can not lock. Front-running not allowed") > 0);
      }
    });

    it("Should be locked if lock method returns success", async () => {
      const isLocked = await registrar.isLocked("Hello Name");
      expect(isLocked).to.be.true;
    });

    it("Should lock an expired lock", async () => {
      await registrar.forceExpireLock("Hello Name", accounts[0].address);
      const reg2 = await registrar.connect(accounts[2]);
      expect(await reg2.lock("Hello Name", { gasLimit: underGas })).to.emit(registrar, "Locked");
    });
  });

  describe("Registration", () => {
    it("Should not register name with expired lock", async () => {
      try {
        const price = await registrar.calculatePrice("Hello Name");
        await registrar.registerName("Hello Name", { value: price });
      } catch (err) {
        assert(err.toString().indexOf("Lock expired") > 0);
      }
    });

    it("Should not register name without prior lock", async () => {
      try {
        const price = await registrar.calculatePrice("Hello Unlocked Name");
        await registrar.registerName("Hello Unlocked Name", { value: price });
      } catch (err) {
        assert(err.toString().indexOf("No lock found for name/sender pair") > 0);
      }
    });

    it("Should register a locked name", async () => {
      const reg2 = await registrar.connect(accounts[2]);
      expect(await reg2.lock("Hello Unlocked Name", { gasLimit: underGas })).to.emit(reg2, "Locked");
      const price = await registrar.calculatePrice("Hello Unlocked Name");
      expect(await reg2.registerName("Hello Unlocked Name", { value: price })).to.emit(reg2, "Registered");
    });

    it("Should not register an already registered name", async () => {
      const reg2 = await registrar.connect(accounts[2]);
      const price = await registrar.calculatePrice("Hello Name");
      try {
        await reg2.registerName("Hello Name", { value: price });
      } catch (err) {
        assert(err.toString().indexOf("Your registration is still active") > 0);
      }
    });

    it("Should register an expired name by same user", async () => {
      await registrar.forceExpireRegistration("Hello Name", accounts[2].address);
      const reg2 = await registrar.connect(accounts[2]);
      const price = await registrar.calculatePrice("Hello Name");
      expect(await reg2.registerName("Hello Name", { value: price })).to.emit(reg2, "Renew");
    });

    it("Should renew an expired name by same user", async () => {
      await registrar.forceExpireRegistration("Hello Name", accounts[2].address);
      const reg2 = await registrar.connect(accounts[2]);
      const price = await registrar.calculatePrice("Hello Name");
      expect(await reg2.renewRegistration("Hello Name")).to.emit(reg2, "Renew");
    });    
  });
});

const { createGasProxy, logGasLib } = require("./../gasProxy");

const StateAssertionChannel = artifacts.require("StateAssertionChannel");
const App = artifacts.require("App");

contract("StateAssertionChannel", async accounts => {
    it("1. deploy, deposits, triggerdispute, assertstate, payout", async () => {
        const gasLib = [];
        const player0 = accounts[0];
        const player1 = accounts[1];
        const bondAmount = 20;
        const StateAssertion = createGasProxy(StateAssertionChannel, gasLib, web3);
        const channel = await StateAssertion.new(player0, player1, 10, accounts[2], bondAmount);

        /// deposit ///
        const depositValue = 10;
        await channel.deposit({ from: player0, value: depositValue });
        assert.equal(depositValue, (await channel.balance(player0)).toNumber());

        await channel.deposit({ from: player1, value: depositValue });
        assert.equal(depositValue, (await channel.balance(player1)).toNumber());

        /// setstate ///
        const dummyHstate = "0x3456789873654523678728675367827445678765678765678987655665676567";
        const dummyRound = 1;
        const dummyFirstTurn = true;
        const player0Sig = sigTools.chopUpSig(
            await sigTools.hashAndSignState(dummyHstate, dummyRound, dummyFirstTurn, channel.address, player0)
        );
        const player1Sig = sigTools.chopUpSig(
            await sigTools.hashAndSignState(dummyHstate, dummyRound, dummyFirstTurn, channel.address, player1)
        );
        const setStateResult = await channel.setstate(
            [...player0Sig, ...player1Sig],
            dummyRound,
            dummyFirstTurn,
            dummyHstate,

            { from: player1 }
        );
        assert.equal(setStateResult.logs[0].args["bestround"].toNumber(), dummyRound);
        assert.equal(setStateResult.logs[0].args["hstate"], dummyHstate);

        /// triggerDispute ///
        const state = "0xface";
        const dummyPrevState = sigTools.hashBytes(state);
        const dummyNewState = "0x3456789873654523678728675367827445678765678765678987655665676568";
        let inputBytes = "0x";
        for (let index = 0; index < 2; index++) {
            inputBytes += "5";
        }

        const command = "1";
        await channel.triggerdispute({ from: player1 });

        /// assert states ///
        const hashedBalances = sigTools.hashBalances(10, 10);
        await channel.assertState(
            dummyHstate,
            hashedBalances,
            inputBytes,
            command,

            dummyHstate,
            accounts[5],
            "0x00000000000000000000000000000000",
            0,
            "0x00000000000000000000000000000000",

            { from: player0, value: bondAmount }
        );
        // TODO: check the event is raised here

        const inputHash = sigTools.hashBytes(inputBytes);
        const assertionHash = sigTools.hashAssertion(player0, inputHash, command, hashedBalances);
        // accept and payout
        await channel.resolve(
            10,
            10,
            dummyHstate,
            
            assertionHash,
            player0,
            inputHash,
            command,
            hashedBalances,

            { from: player1 }
        );

        // TODO: payout still required
        logGasLib(gasLib);
    });

    it("2. deploy, deposits, triggerdispute, assertstate, challengeCommand, payout", async () => {
        const gasLib = [];
        const player0 = accounts[0];
        const player1 = accounts[1];
        const bondAmount = 20;
        const AppContract = await App.new();

        const StateAssertion = createGasProxy(StateAssertionChannel, gasLib, web3);
        const channel = await StateAssertion.new(player0, player1, 10, AppContract.address, bondAmount);

        /// deposit ///
        const depositValue = 10;
        await channel.deposit({ from: player0, value: depositValue });
        assert.equal(depositValue, (await channel.balance(player0)).toNumber());

        await channel.deposit({ from: player1, value: depositValue });
        assert.equal(depositValue, (await channel.balance(player1)).toNumber());

        /// setstate ///
        const state = "0xface";
        const dummyHstate = sigTools.hashBytes(state);
        //const dummyHstate = "0x3456789873654523678728675367827445678765678765678987655665676567";
        const dummyRound = 1;
        const dummyFirstTurn = true;
        const player0Sig = sigTools.chopUpSig(
            await sigTools.hashAndSignState(dummyHstate, dummyRound, dummyFirstTurn, channel.address, player0)
        );
        const player1Sig = sigTools.chopUpSig(
            await sigTools.hashAndSignState(dummyHstate, dummyRound, dummyFirstTurn, channel.address, player1)
        );
        const setStateResult = await channel.setstate(
            [...player0Sig, ...player1Sig],
            dummyRound,
            dummyFirstTurn,
            dummyHstate,
            { from: player1 }
        );
        assert.equal(setStateResult.logs[0].args["bestround"].toNumber(), dummyRound);
        assert.equal(setStateResult.logs[0].args["hstate"], dummyHstate);

        /// triggerDispute ///
        const stateOff = "0xofff";
        const dummyNewState = sigTools.hashBytes(stateOff);
        let inputBytes = "0x";
        for (let index = 0; index < 2; index++) {
            inputBytes += "5";
        }

        const command = "1";
        await channel.triggerdispute({ from: player1 });

        /// assert states ///

        await channel.assertState(
            dummyHstate,
            dummyNewState,
            inputBytes,
            command,

            dummyHstate,
            accounts[5],
            "0x00000000000000000000000000000000",
            0,
            "0x00000000000000000000000000000000",

            { from: player0, value: bondAmount }
        );

        // TODO: check the event is raised here
        const inputHash = sigTools.hashBytes(inputBytes);
        const assertionHash = sigTools.hashAssertion(player0, inputHash, command, dummyNewState);
        await channel.challengeCommand(
            state,
            inputBytes,

            dummyHstate,
            assertionHash,
            player0,
            inputHash,
            command,
            dummyNewState,

            { from: player1 }
        );

        const hashedBalances = sigTools.hashBalances(10, 10);

        await channel.assertState(
            dummyNewState,
            hashedBalances,
            inputBytes,
            command,

            dummyHstate,
            player0,
            inputHash,
            command,
            dummyNewState,

            { from: player1, value: bondAmount }
        );

        const resolveAssertionHash = sigTools.hashAssertion(player1, inputHash, command, hashedBalances);
        // accept and payout
        await channel.resolve(
            10,
            10,

            dummyNewState,
            resolveAssertionHash,
            player1,
            inputHash,
            command,
            hashedBalances,

            { from: player0 }
        );

        // TODO: payout still required
        logGasLib(gasLib);
    });

    it("3. deploy, deposits, triggerdispute, assertstate, challengeCommand (false)", async () => {
        const gasLib = [];
        const player0 = accounts[0];
        const player1 = accounts[1];
        const bondAmount = 20;
        const AppContract = await App.new();

        const StateAssertion = createGasProxy(StateAssertionChannel, gasLib, web3);
        const channel = await StateAssertion.new(player0, player1, 10, AppContract.address, bondAmount);

        /// deposit ///
        const depositValue = 10;
        await channel.deposit({ from: player0, value: depositValue });
        assert.equal(depositValue, (await channel.balance(player0)).toNumber());

        await channel.deposit({ from: player1, value: depositValue });
        assert.equal(depositValue, (await channel.balance(player1)).toNumber());

        /// setstate ///
        const state = "0xface";
        const dummyHstate = sigTools.hashBytes(state);
        //const dummyHstate = "0x3456789873654523678728675367827445678765678765678987655665676567";
        const dummyRound = 1;
        const dummyFirstTurn = true;
        const player0Sig = sigTools.chopUpSig(
            await sigTools.hashAndSignState(dummyHstate, dummyRound, dummyFirstTurn, channel.address, player0)
        );
        const player1Sig = sigTools.chopUpSig(
            await sigTools.hashAndSignState(dummyHstate, dummyRound, dummyFirstTurn, channel.address, player1)
        );
        const setStateResult = await channel.setstate(
            [...player0Sig, ...player1Sig],
            dummyRound,
            dummyFirstTurn,
            dummyHstate,
            { from: player1 }
        );
        assert.equal(setStateResult.logs[0].args["bestround"].toNumber(), dummyRound);
        assert.equal(setStateResult.logs[0].args["hstate"], dummyHstate);

        /// triggerDispute ///
        const stateOff = "0xofffgg";
        const dummyNewState = sigTools.hashBytes(stateOff);
        let inputBytes = "0x";
        for (let index = 0; index < 2; index++) {
            inputBytes += "5";
        }

        const command = "1";
        await channel.triggerdispute({ from: player1 });

        /// assert states ///
        await channel.assertState(
            dummyHstate,
            dummyNewState,
            inputBytes,
            command,

            dummyHstate,
            accounts[5],
            "0x00000000000000000000000000000000",
            0,
            "0x00000000000000000000000000000000",

            { from: player0, value: bondAmount }
        );




        // TODO: check the event is raised here

        // await channel.challengeCommand(state, inputBytes, { from: player1 });

        const inputHash = sigTools.hashBytes(inputBytes);
        const assertionHash = sigTools.hashAssertion(player0, inputHash, command, dummyNewState);
        await channel.challengeCommand(
            state,
            inputBytes,

            dummyHstate,
            assertionHash,
            player0,
            inputHash,
            command,
            dummyNewState,

            { from: player1 }
        );




        logGasLib(gasLib);
    });

    it("4. deploy, deposits, triggerdispute, assertstate, timeout", async () => {
        const gasLib = [];
        const player0 = accounts[0];
        const player1 = accounts[1];
        const bondAmount = 20;
        const AppContract = await App.new();

        const StateAssertion = createGasProxy(StateAssertionChannel, gasLib, web3);
        const channel = await StateAssertion.new(player0, player1, 0, AppContract.address, bondAmount);

        /// deposit ///
        const depositValue = 10;
        await channel.deposit({ from: player0, value: depositValue });
        assert.equal(depositValue, (await channel.balance(player0)).toNumber());

        await channel.deposit({ from: player1, value: depositValue });
        assert.equal(depositValue, (await channel.balance(player1)).toNumber());

        /// setstate ///
        const state = "0xface";
        const dummyHstate = sigTools.hashBytes(state);
        //const dummyHstate = "0x3456789873654523678728675367827445678765678765678987655665676567";
        const dummyRound = 1;
        const dummyFirstTurn = true;
        const player0Sig = sigTools.chopUpSig(
            await sigTools.hashAndSignState(dummyHstate, dummyRound, dummyFirstTurn, channel.address, player0)
        );
        const player1Sig = sigTools.chopUpSig(
            await sigTools.hashAndSignState(dummyHstate, dummyRound, dummyFirstTurn, channel.address, player1)
        );
        const setStateResult = await channel.setstate(
            [...player0Sig, ...player1Sig],
            dummyRound,
            dummyFirstTurn,
            dummyHstate,
            { from: player1 }
        );
        assert.equal(setStateResult.logs[0].args["bestround"].toNumber(), dummyRound);
        assert.equal(setStateResult.logs[0].args["hstate"], dummyHstate);

        /// triggerDispute ///
        const stateOff = "0xofff";
        const dummyNewState = sigTools.hashBytes(stateOff);
        let inputBytes = "0x";
        for (let index = 0; index < 0; index++) {
            inputBytes += "5";
        }

        const command = "1";
        await channel.triggerdispute({ from: player1 });

        /// assert states ///
        await channel.assertState(
            dummyHstate,
            dummyNewState,
            inputBytes,
            command,

            dummyHstate,
            accounts[5],
            "0x00000000000000000000000000000000",
            0,
            "0x00000000000000000000000000000000",

            { from: player0, value: bondAmount }
        );

        await channel.timeout();

        // TODO: payout still required
        logGasLib(gasLib);
    });

    it("5. deploy, deposits, triggerdispute, assertstate (small)", async () => {
        const gasLib = [];
        const player0 = accounts[0];
        const player1 = accounts[1];
        const bondAmount = 20;
        const AppContract = await App.new();

        const StateAssertion = createGasProxy(StateAssertionChannel, gasLib, web3);
        const channel = await StateAssertion.new(player0, player1, 0, AppContract.address, bondAmount);

        /// deposit ///
        const depositValue = 10;
        await channel.deposit({ from: player0, value: depositValue });
        assert.equal(depositValue, (await channel.balance(player0)).toNumber());

        await channel.deposit({ from: player1, value: depositValue });
        assert.equal(depositValue, (await channel.balance(player1)).toNumber());

        /// setstate ///
        const state = "0xface";
        const dummyHstate = sigTools.hashBytes(state);
        //const dummyHstate = "0x3456789873654523678728675367827445678765678765678987655665676567";
        const dummyRound = 1;
        const dummyFirstTurn = true;
        const player0Sig = sigTools.chopUpSig(
            await sigTools.hashAndSignState(dummyHstate, dummyRound, dummyFirstTurn, channel.address, player0)
        );
        const player1Sig = sigTools.chopUpSig(
            await sigTools.hashAndSignState(dummyHstate, dummyRound, dummyFirstTurn, channel.address, player1)
        );
        const setStateResult = await channel.setstate(
            [...player0Sig, ...player1Sig],
            dummyRound,
            dummyFirstTurn,
            dummyHstate,
            { from: player1 }
        );
        assert.equal(setStateResult.logs[0].args["bestround"].toNumber(), dummyRound);
        assert.equal(setStateResult.logs[0].args["hstate"], dummyHstate);

        /// triggerDispute ///
        const stateOff = "0xofff";
        const dummyNewState = sigTools.hashBytes(stateOff);
        let inputBytes = "0x";
        for (let index = 0; index < 0; index++) {
            inputBytes += "5";
        }

        const command = "1";
        await channel.triggerdispute({ from: player1 });

        /// assert states ///
        await channel.assertState(
            dummyHstate,
            dummyNewState,
            inputBytes,
            command,

            dummyHstate,
            accounts[5],
            "0x00000000000000000000000000000000",
            0,
            "0x00000000000000000000000000000000",

            { from: player0, value: bondAmount }
        );


        // TODO: payout still required
        logGasLib(gasLib);
    });

    it("6. deploy, deposits, triggerdispute, assertstate (large)", async () => {
        const gasLib = [];
        const player0 = accounts[0];
        const player1 = accounts[1];
        const bondAmount = 20;
        const AppContract = await App.new();

        const StateAssertion = createGasProxy(StateAssertionChannel, gasLib, web3);
        const channel = await StateAssertion.new(player0, player1, 0, AppContract.address, bondAmount);

        /// deposit ///
        const depositValue = 10;
        await channel.deposit({ from: player0, value: depositValue });
        assert.equal(depositValue, (await channel.balance(player0)).toNumber());

        await channel.deposit({ from: player1, value: depositValue });
        assert.equal(depositValue, (await channel.balance(player1)).toNumber());

        /// setstate ///
        const state = "0xface";
        const dummyHstate = sigTools.hashBytes(state);
        //const dummyHstate = "0x3456789873654523678728675367827445678765678765678987655665676567";
        const dummyRound = 1;
        const dummyFirstTurn = true;
        const player0Sig = sigTools.chopUpSig(
            await sigTools.hashAndSignState(dummyHstate, dummyRound, dummyFirstTurn, channel.address, player0)
        );
        const player1Sig = sigTools.chopUpSig(
            await sigTools.hashAndSignState(dummyHstate, dummyRound, dummyFirstTurn, channel.address, player1)
        );
        const setStateResult = await channel.setstate(
            [...player0Sig, ...player1Sig],
            dummyRound,
            dummyFirstTurn,
            dummyHstate,
            { from: player1 }
        );
        assert.equal(setStateResult.logs[0].args["bestround"].toNumber(), dummyRound);
        assert.equal(setStateResult.logs[0].args["hstate"], dummyHstate);

        /// triggerDispute ///
        const stateOff = "0xofff";
        const dummyNewState = sigTools.hashBytes(stateOff);
        let inputBytes = "0x";
        for (let index = 0; index < 10000; index++) {
            inputBytes += "5";
        }

        const command = "1";
        await channel.triggerdispute({ from: player1 });

        /// assert states ///
        await channel.assertState(
            dummyHstate,
            dummyNewState,
            inputBytes,
            command,

            dummyHstate,
            accounts[5],
            "0x00000000000000000000000000000000",
            0,
            "0x00000000000000000000000000000000",

            { from: player0, value: bondAmount }
        );

        // TODO: payout still required
        logGasLib(gasLib);
    });
});

const sigTools = {
    // hashWithAddress: (hState, address) => {
    //     return web3.utils.soliditySha3({ t: "bytes32", v: hState }, { t: "address", v: address });
    // },

    hashAndSignState: async (hState, round, firstturn, channelAddress, playerAddress) => {
        let msg = web3.utils.soliditySha3(
            { t: "bytes32", v: hState },
            { t: "uint256", v: round },
            { t: "bool", v: firstturn },
            { t: "address", v: channelAddress }
        );
        const sig = await web3.eth.sign(msg, playerAddress);
        return sig;
    },

    hashBalances: (balance0, balance1) => {
        return web3.utils.soliditySha3({ t: "uint256", v: balance0 }, { t: "uint256", v: balance1 });
    },

    hashBytes: byteString => {
        return web3.utils.soliditySha3({ t: "bytes", v: byteString });
    },

    hashAssertion: (asserter, inputHash, command, assertedState) => {
        return web3.utils.soliditySha3(
            { t: "address", v: asserter },
            { t: "bytes32", v: inputHash },
            { t: "uint256", v: command },
            { t: "bytes32", v: assertedState }
        );
    },

    // hashAndSignClose: async (hState, round, channelAddress, playerAddress) => {
    //     let msg = web3.utils.soliditySha3(
    //         { t: "string", v: "close" },
    //         { t: "bytes32", v: hState },
    //         { t: "uint256", v: round },
    //         { t: "address", v: channelAddress }
    //     );
    //     const sig = await web3.eth.sign(msg, playerAddress);
    //     return sig;
    // },

    // hashAndSignLock: async (channelCounter, round, battleShipAddress, playerAddress) => {
    //     let msg = web3.utils.soliditySha3(
    //         { t: "string", v: "lock" },
    //         { t: "uint256", v: channelCounter },
    //         { t: "uint256", v: round },
    //         { t: "address", v: battleShipAddress }
    //     );
    //     const sig = await web3.eth.sign(msg, playerAddress);
    //     return sig;
    // },

    chopUpSig: sig => {
        const removedHexNotation = sig.slice(2);
        var r = `0x${removedHexNotation.slice(0, 64)}`;
        var s = `0x${removedHexNotation.slice(64, 128)}`;
        var v = `0x${removedHexNotation.slice(128, 130)}`;
        return [v, r, s];
    }
};

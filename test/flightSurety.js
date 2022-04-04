var Test = require('../config/testConfig.js');
var BigNumber = require('bignumber.js');

contract('Flight Surety Tests', async (accounts) => {

  var config;
  before('setup contract', async () => {
    config = await Test.Config(accounts);
    await config.flightSuretyData.authorizeCaller(config.flightSuretyApp.address);
  });

  /****************************************************************************************/
  /* Operations and Settings                                                              */
  /****************************************************************************************/

  it(`(multiparty) has correct initial isOperational() value`, async function () {

    // Get operating status
    let status = await config.flightSuretyData.isOperational.call();
    assert.equal(status, true, "Incorrect initial operating status value");

  });

  it(`(multiparty) can block access to setOperatingStatus() for non-Contract Owner account`, async function () {

      // Ensure that access is denied for non-Contract Owner account
      let accessDenied = false;
      try 
      {
          await config.flightSuretyData.setOperatingStatus(false, { from: config.testAddresses[2] });
      }
      catch(e) {
          accessDenied = true;
      }
      assert.equal(accessDenied, true, "Access not restricted to Contract Owner");
            
  });

  it(`(multiparty) can allow access to setOperatingStatus() for Contract Owner account`, async function () {

      // Ensure that access is allowed for Contract Owner account
      let accessDenied = false;
      try 
      {
          await config.flightSuretyData.setOperatingStatus(false);
      }
      catch(e) {
          accessDenied = true;
      }
      assert.equal(accessDenied, false, "Access not restricted to Contract Owner");
      
  });

  it(`(multiparty) can block access to functions using requireIsOperational when operating status is false`, async function () {

      await config.flightSuretyData.setOperatingStatus(false);

      let reverted = false;
      try 
      {
          await config.flightSurety.setTestingMode();
      }
      catch(e) {
          reverted = true;
      }
      assert.equal(reverted, true, "Access not blocked for requireIsOperational");      

      // Set it back for other tests to work
      await config.flightSuretyData.setOperatingStatus(true);

  });

  it('(airline) cannot register an Airline using registerAirline() if the caller is not funded', async () => {
    
    // ARRANGE
    let newAirline = accounts[2];

    // ACT
    let checkFunded = false;
    try {
        await config.flightSuretyApp.registerAirline(newAirline, {from: config.firstAirline});
    }
    catch(e) {
        checkFunded = true;
    }

    // ASSERT
    assert.equal(checkFunded, true, "Airline should not be able to register another airline if it hasn't provided funding");

  });

  it('(airline) can fund a registered airline', async () => {
      let isFunded = await config.flightSuretyData.isFundedAirline(config.firstAirline);
      assert.equal(isFunded, false, "firstAirline already funded");

      await config.flightSuretyData.fund({from: config.firstAirline, value: 1e19});

      isFunded = await config.flightSuretyData.isFundedAirline(config.firstAirline);
      assert.equal(isFunded, true, "firstAirline not funded");

  });

  it('(airline) can register an Airline directly from a funded airline when there are less than 4 registered airlines', async () => {
      let airline_2 = accounts[2];

      let isRegistered = await config.flightSuretyData.isRegisteredAirline(airline_2);
      assert.equal(isRegistered, false, "airline_2 already registered");

      await config.flightSuretyApp.registerAirline(airline_2, {from: config.firstAirline});

      isRegistered = await config.flightSuretyData.isRegisteredAirline(airline_2);
      assert.equal(isRegistered, true, "airline_2 not registered");
  });

  it('(airline) can register an Airline iff there are >= 50% approvals when there are at least 4 registered airlines', async () => {
      // register airlines until the total count reaches 4
      let airline_3 = accounts[3];
      let airline_4 = accounts[4];
      await config.flightSuretyApp.registerAirline(airline_3, {from: config.firstAirline});
      await config.flightSuretyApp.registerAirline(airline_4, {from: config.firstAirline});

      // first approval
      let airline_5 = accounts[5];
      await config.flightSuretyApp.registerAirline(airline_5, {from: config.firstAirline});
      let isRegistered = await config.flightSuretyData.isRegisteredAirline(airline_5);
      assert.equal(isRegistered, false, "airline_5 is registered with only 1/4 approval");

      // fund airline_2 so it can approve airline_5
      let airline_2 = accounts[2];
      await config.flightSuretyData.fund({from: airline_2, value: 1e19});
      isRegistered = await config.flightSuretyData.isRegisteredAirline(airline_2);
      assert.equal(isRegistered, true, "airline_5 is not registered with 2/4 approval");
    });

    it('(passenger) can purchase flight insurance', async () => {
        let passenger = accounts[6];
        let airline = config.firstAirline;
        let flight = 'AA123';
        let timestamp = Math.floor(Date.now() / 1000);
        let paidInsurance = 1e17;

        await config.flightSuretyData.buy(airline, flight, timestamp, {from: passenger, value: paidInsurance});
        let loggedInsurance = await config.flightSuretyData.getInsuranceAmount(passenger, airline, flight, timestamp);
        assert.equal(paidInsurance, loggedInsurance, "insurance amounts not match")
    });
});

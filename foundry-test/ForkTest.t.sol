/**
 * Spdx-License-Identifier: UNLICENSED
 */
pragma solidity ^0.8.0;

import {Test, Vm, console2} from "forge-std/Test.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {AddressBookInterface} from "./protocol-interfaces/AddressBookInterface.sol";
import {WhitelistInterface} from "./protocol-interfaces/WhitelistInterface.sol";
// import {ControllerInterface} from "./protocol-interfaces/ControllerInterface.sol";
import {IUniswapV3Factory} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {SqrtPriceLibrary} from "@uniswap/hooks-utils/libraries/SqrtPriceLibrary.sol"; 
import {FullMath} from "@uniswap/v3-core/contracts/libraries/FullMath.sol";

contract ForkTest is Test{
// 22 JAN 1 USD = 
// 06 FEB 1 USD =

//  3667304224422582000000000000000000
//  3651299839757684000000000000000000

      IUniswapV3Factory constant FACTORY_V3 = IUniswapV3Factory(address(0xAfE208a311B21f13EF87E33A90049fC17A7acDEc));	
	uint256 constant JAN_22 = 57139242;
	uint256 constant JAN_22_UNIX = 1769040000;
	uint256 constant wadSpotPriceJan22 = 3667304224422582000000000000000000;
	
	uint256 constant FEB_06 = 59212842;
	uint256 constant FEB_06_UNIX = 1770364800;
	uint256 constant wadSpotPriceFeb06 = 3651299839757684000000000000000000;

	IERC20 constant STABLE_USD = IERC20(address(0x48065fbBE25f71C9282ddf5e1cD6D6A887483D5e));
	IERC20 constant COP = IERC20(address(0x8A567e2aE79CA692Bd748aB832081C45de4041eA));

	bool constant CALL = false;
	uint256 CELO_FORK;

	address COP_USD;
	
	Vm.Wallet userWallet;
	AddressBookInterface addressBook;
	WhitelistInterface whitelist;
	address optionTokenFactory;
//	ControllerInterface controller;

	function setUp() public {
	 	  // 1. Read the fork RPC
		 CELO_FORK =  vm.createSelectFork(vm.envString("CELO_MAINNET_RPC"));
		 vm.rollFork(JAN_22);
		  // 2. Create a user address
		  if (userAddress() == address(0x00)){
		       userWallet = vm.createWallet("USER_WALLET");
		   }
		   
		  // 3. Find the collateral address in the network
		  // 4. Deploy the AddressBook

		  if (address(addressBook).code.length == uint256(0x00)){
		     addressBook = AddressBookInterface(vm.deployCode("AddressBook.sol"));
		  }
		  assert(address(addressBook).code.length > 0);
		  // 5. Deploy and set the Whitelist
		  if (address(whitelist).code.length == uint256(0x00)){
		     whitelist = WhitelistInterface(vm.deployCode("Whitelist.sol", abi.encode(address(addressBook))));
		  }
		  assert(address(whitelist).code.length > 0);
		  addressBook.setWhitelist(address(whitelist));

		  if (optionTokenFactory.code.length == uint256(0x00)){
		     optionTokenFactory = vm.deployCode(
							"OtokenFactory.sol",
							abi.encode(address(addressBook))
							);
		  }
		  assert(optionTokenFactory.code.length > uint256(0x00));

		  addressBook.setOtokenFactory(optionTokenFactory);

		  COP_USD = FACTORY_V3.getPool(address(STABLE_USD),address(COP), 100);

		 
		  // if (address(controller).code.length == uint256(0x00)){
		  //   controller = ControllerInterface(
		  //   		vm.deployCode(
		  //			"Controller.sol"
		  //	 	)
		  //   );
		  //}
		  // assert(address(controller).code.length > uint256(0x00));
		  // addressBook.setController(address(controller));
		  // controller.initialize(address(addressBook), address(this));

	 }

	 function userAddress() public view returns(address){
	     return userWallet.addr;
	 }

	modifier fork(){vm.selectFork(CELO_FORK); _;}
	function getPriceWad(address pool) internal view returns (uint256 priceWad) {
    		 IUniswapV3Pool p = IUniswapV3Pool(pool);

    		 (uint160 sqrtPriceX96,,,,,,) = p.slot0();

    		 priceWad = FullMath.mulDiv(
        	 	  uint256(sqrtPriceX96),
			  uint256(sqrtPriceX96),
        		  SqrtPriceLibrary.Q192
    			  ) * 1e18;

    		 if (p.token0() == address(STABLE_USD)) {
        	 // price is COP per USD (correct orientation)
        	    return priceWad;
    		  } else {
        	  // invert
        	     return 1e36 / priceWad;
    		  }
	 }


	 function _approveCollateral() public fork() returns(uint256){
	 	  whitelist.whitelistCollateral(address(COP));
		  whitelist.whitelistProduct(
			address(COP),
			address(STABLE_USD),
			address(COP),
			CALL
		   );
	 }

	 function test__fork__writeCallOption() public fork() {
	 	  //=======PRE-CONDITIONS=====
	 	  _approveCollateral();

		  //=========TEST============
	    optionTokenFactory.call(abi.encodeWithSignature("createOtoken(address,address,address,uint256,uint256,bool)", address(COP), address(STABLE_USD), address(COP), wadSpotPriceFeb06, FEB_06_UNIX, CALL));
	 }

	 function test_placeHolder() external{}





	 
	 
}


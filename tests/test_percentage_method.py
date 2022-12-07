from brownie import (
    EkolanceFixedRatioSwap,
    Group2CoinA,
    Group2CoinB,
    interface,
    accounts,
    web3,
)
import pytest


def test_deploy_tokens():
    zero_address = "0x0000000000000000000000000000000000000000"
    deployer = accounts[0]
    user = accounts[1]
    user1 = accounts[2]
    user2 = accounts[3]
    user3 = accounts[4]
    Lp2 = accounts[5]

    get_thousand = web3.toWei(1000, "ether")
    get_fivehundred = web3.toWei(500, "ether")
    get_hundred = web3.toWei(100, "ether")
    get_fifty = web3.toWei(50, "ether")

    mobi_coin = Group2CoinA.deploy(get_thousand, {"from": deployer})
    nina_coin = Group2CoinB.deploy(get_thousand, {"from": deployer})

    mobi_coin_interface = interface.IERC20(mobi_coin.address)
    nina_coin_interface = interface.IERC20(nina_coin.address)

    mobi_coin_interface.mintMore(get_thousand, {"from": user})
    nina_coin_interface.mintMore(get_thousand, {"from": user})

    mobi_coin_interface.mintMore(get_hundred, {"from": user1})
    nina_coin_interface.mintMore(get_hundred, {"from": user1})

    mobi_coin_interface.mintMore(get_hundred, {"from": user2})
    nina_coin_interface.mintMore(get_hundred, {"from": user2})

    mobi_coin_interface.mintMore(get_fifty, {"from": user3})
    nina_coin_interface.mintMore(get_fifty, {"from": user3})

    mobi_coin_interface.mintMore(get_hundred, {"from": Lp2})
    nina_coin_interface.mintMore(get_hundred, {"from": Lp2})

    print(
        f"Deployer Token balance is: {web3.fromWei(mobi_coin.balanceOf(deployer.address), 'ether')} {mobi_coin.symbol()}, {web3.fromWei(nina_coin.balanceOf(deployer.address), 'ether')} {nina_coin.symbol()} "
    )

    print(
        "User Token balance is: ",
        web3.fromWei(mobi_coin_interface.balanceOf(user.address), "ether"),
        mobi_coin_interface.symbol(),
        ",",
        web3.fromWei(nina_coin_interface.balanceOf(user.address), "ether"),
        nina_coin_interface.symbol(),
    )

    return (
        deployer,
        user,
        mobi_coin,
        nina_coin,
        get_thousand,
        get_hundred,
        get_fifty,
        zero_address,
        user1,
        user2,
        user3,
        Lp2,
        get_fivehundred,
    )


def test_ekolance():
    (
        deployer,
        user,
        mobi_coin,
        nina_coin,
        get_thousand,
        get_hundred,
        get_fifty,
        zero_address,
        user1,
        user2,
        user3,
        Lp2,
        get_fivehundred,
    ) = test_deploy_tokens()

    ekolance_contract = EkolanceFixedRatioSwap.deploy(
        mobi_coin.address, nina_coin.address, {"from": deployer}
    )
    assert ekolance_contract.reserve0() == 0
    assert ekolance_contract.reserve1() == 0
    # assert ekolance_contract.TotalSupply() == 0

    print("State variables are okay!")
    print("Adding Liquidity!!")
    tx1 = mobi_coin.approve(ekolance_contract.address, get_thousand, {"from": deployer})
    tx2 = nina_coin.approve(ekolance_contract.address, get_thousand, {"from": deployer})

    tx1a = mobi_coin.approve(ekolance_contract.address, get_hundred, {"from": user})
    tx2a = nina_coin.approve(ekolance_contract.address, get_hundred, {"from": user})

    mobi_coin.approve(ekolance_contract.address, get_hundred, {"from": user1})
    nina_coin.approve(ekolance_contract.address, get_hundred, {"from": user1})

    mobi_coin.approve(ekolance_contract.address, get_hundred, {"from": user2})
    nina_coin.approve(ekolance_contract.address, get_hundred, {"from": user2})

    mobi_coin.approve(ekolance_contract.address, get_fifty, {"from": user3})
    nina_coin.approve(ekolance_contract.address, get_fifty, {"from": user3})

    mobi_coin.approve(ekolance_contract.address, get_hundred, {"from": Lp2})
    nina_coin.approve(ekolance_contract.address, get_hundred, {"from": Lp2})
    # tx1.info()

    # tx2.info()
    print("Approve success for deployer!")
    tx3 = ekolance_contract.addLiquidity(
        get_fivehundred, get_thousand, {"from": deployer}
    )
    lp2tx = ekolance_contract.addLiquidity(get_fifty, get_hundred, {"from": Lp2})
    print("Logging add liquidity events...")
    print(tx3.events["AddLiquidity"])
    print(lp2tx.events["AddLiquidity"])
    # print(tx3.events["Mint"])

    print("logging reserves")
    print(f"The pool reserve balances are : {ekolance_contract.getReserves()}")
    # print(f"The total supply of shares = {ekolance_contract.TotalSupply()}")
    # shares_deployer = ekolance_contract.balanceOf(deployer.address)
    # shares_lp2 = ekolance_contract.balanceOf(Lp2.address)
    # print(f"The deployer/ LP1 total shares is = {shares_deployer} ")
    # print(f"The LP2 total shares is = {shares_lp2} ")

    # tx3.info()
    # print(web3.fromWei(ekolance_contract.balanceOf(deployer.address), "ether"))

    tx4 = ekolance_contract.swap(mobi_coin.address, get_hundred, {"from": user})
    ekolance_contract.swap(mobi_coin.address, get_hundred, {"from": user1})
    ekolance_contract.swap(nina_coin.address, get_hundred, {"from": user2})
    txninacoin = ekolance_contract.swap(nina_coin.address, get_fifty, {"from": user3})
    print("tx's complete!")
    tx4.info()
    txninacoin.info()

    print("logging reserves")
    print(f"The pool reserve balances are : {ekolance_contract.getReserves()}")
    print(
        f"Logging the percentages : {ekolance_contract.Apercentage(deployer)}, {ekolance_contract.Bpercentage(deployer)}"
    )

    print(
        f"Logging the percentages of LP2 : {ekolance_contract.Apercentage(Lp2)}, {ekolance_contract.Bpercentage(Lp2)}"
    )

    tx5 = ekolance_contract.removeLiquidity({"from": deployer})
    tx5.info()
    print("logging reserves")
    print(f"The pool reserve balances are : {ekolance_contract.getReserves()}")

    ekolance_contract.removeLiquidity({"from": Lp2})
    print("logging reserves")
    print(f"The pool reserve balances are : {ekolance_contract.getReserves()}")

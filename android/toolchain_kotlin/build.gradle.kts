plugins { id("com.android.asset-pack") }
assetPack {
    packName = "toolchain_kotlin"
    dynamicDelivery { deliveryType.set("on-demand") }
}

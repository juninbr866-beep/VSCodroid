plugins { id("com.android.asset-pack") }
assetPack {
    packName = "toolchain_dart"
    dynamicDelivery { deliveryType.set("on-demand") }
}

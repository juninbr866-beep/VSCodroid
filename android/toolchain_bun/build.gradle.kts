plugins { id("com.android.asset-pack") }
assetPack {
    packName.set("toolchain_bun")
    dynamicDelivery { deliveryType.set("on-demand") }
}

plugins { id("com.android.asset-pack") }
assetPack {
    packName.set("toolchain_zig")
    dynamicDelivery { deliveryType.set("on-demand") }
}

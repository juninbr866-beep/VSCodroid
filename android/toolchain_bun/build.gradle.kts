plugins {
    id("com.android.asset-pack")
}

android {
    assetPack {
        packName = "toolchain_bun"
        dynamicDelivery {
            onDemand = true
        }
    }
}

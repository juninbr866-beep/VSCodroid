plugins {
    id("com.android.asset-pack")
}

android {
    assetPack {
        packName = "toolchain_perl"
        dynamicDelivery {
            onDemand = true
        }
    }
}

plugins {
    id("com.android.asset-pack")
}

android {
    assetPack {
        packName = "toolchain_php"
        dynamicDelivery {
            onDemand = true
        }
    }
}

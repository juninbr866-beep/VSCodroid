plugins {
    id("com.android.asset-pack")
}

android {
    assetPack {
        packName = "toolchain_lua"
        dynamicDelivery {
            onDemand = true
        }
    }
}

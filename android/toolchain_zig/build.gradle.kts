plugins {
    id("com.android.asset-pack")
}

android {
    assetPack {
        packName = "toolchain_zig"
        dynamicDelivery {
            onDemand = true
        }
    }
}

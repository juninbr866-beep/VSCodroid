plugins {
    id("com.android.asset-pack")
}

android {
    assetPack {
        packName = "toolchain_deno"
        dynamicDelivery {
            onDemand = true
        }
    }
}

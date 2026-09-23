plugins {
    kotlin("jvm") version "2.4.20"
    application
}

application {
    mainClass = "MainKt"
}

kotlin {
    jvmToolchain(21)
}

import java.util.Properties

plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.android)
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.kotlin.ksp)
    alias(libs.plugins.hilt.android)
    alias(libs.plugins.kotlin.serialization)
}

android {
    namespace = "com.caddieai.android"
    compileSdk = 36

    defaultConfig {
        applicationId = "com.caddieai.android"
        minSdk = 26
        targetSdk = 36
        versionCode = 1
        versionName = "1.0"

        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"

        val localProps = Properties()
        val localPropsFile = File(rootDir, "local.properties")
        if (localPropsFile.exists()) localProps.load(localPropsFile.inputStream())
        buildConfigField("String", "GOLF_COURSE_API_KEY", "\"${localProps.getProperty("GOLF_COURSE_API_KEY", "")}\"")
        buildConfigField("String", "MAPBOX_API_KEY", "\"${localProps.getProperty("MAPBOX_API_KEY", "")}\"")
        buildConfigField("String", "LLM_PROXY_ENDPOINT", "\"${localProps.getProperty("LLM_PROXY_ENDPOINT", "")}\"")
        buildConfigField("String", "LLM_PROXY_API_KEY", "\"${localProps.getProperty("LLM_PROXY_API_KEY", "")}\"")
        buildConfigField("String", "LOGGING_ENDPOINT", "\"${localProps.getProperty("LOGGING_ENDPOINT", "")}\"")
        buildConfigField("String", "LOGGING_API_KEY", "\"${localProps.getProperty("LOGGING_API_KEY", "")}\"")
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }
    kotlinOptions {
        jvmTarget = "11"
    }
    buildFeatures {
        compose = true
        buildConfig = true
    }
}

dependencies {
    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.lifecycle.runtime.ktx)
    implementation(libs.androidx.lifecycle.viewmodel.compose)
    implementation(libs.androidx.lifecycle.runtime.compose)
    implementation(libs.androidx.activity.compose)
    implementation(platform(libs.androidx.compose.bom))
    implementation(libs.androidx.compose.ui)
    implementation(libs.androidx.compose.ui.graphics)
    implementation(libs.androidx.compose.ui.tooling.preview)
    implementation(libs.androidx.compose.material3)
    implementation(libs.androidx.compose.material.icons.extended)
    implementation(libs.androidx.navigation.compose)
    implementation(libs.hilt.android)
    ksp(libs.hilt.android.compiler)
    implementation(libs.hilt.navigation.compose)
    implementation(libs.androidx.datastore.preferences)
    implementation(libs.kotlinx.coroutines.android)
    implementation(libs.kotlinx.serialization.json)
    implementation(libs.okhttp)
    implementation(libs.okhttp.logging.interceptor)
    implementation(libs.mapbox.maps)
    implementation(libs.billing.ktx)
    implementation(libs.play.services.ads)
    implementation(libs.user.messaging.platform)
    implementation(libs.coil.compose)
    implementation(libs.work.runtime.ktx)
    implementation(libs.hilt.work)
    ksp(libs.hilt.compiler.androidx)
    implementation(libs.play.services.location)
    implementation(libs.androidx.core.splashscreen)
    implementation(libs.play.review.ktx)

    testImplementation(libs.junit)
    androidTestImplementation(libs.androidx.junit)
    androidTestImplementation(libs.androidx.espresso.core)
    androidTestImplementation(platform(libs.androidx.compose.bom))
    androidTestImplementation(libs.androidx.compose.ui.test.junit4)
    debugImplementation(libs.androidx.compose.ui.tooling)
    debugImplementation(libs.androidx.compose.ui.test.manifest)
}

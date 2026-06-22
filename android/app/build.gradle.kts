import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing credentials live in android/key.properties (not committed).
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
}

android {
    namespace = "com.example.expense_tracker"
    compileSdk = flutter.compileSdkVersion
    // Pinned to the highest NDK required across plugins (backward compatible).
    ndkVersion = "27.0.12077973"

    compileOptions {
        // Required by flutter_local_notifications (uses newer java.time APIs).
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        // Klaro app identity (namespace above is unchanged — Kotlin sources keep their package).
        applicationId = "com.premm.klaro"
        // another_telephony requires API 23+ (SMS APIs). Phone is API 31.
        minSdk = 23
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // Two distributions of the same app (Phase 7.3):
    //   • full — direct-APK "power" build WITH SMS auto-capture (src/full manifest
    //            adds the SMS permissions + receiver). Build with
    //            --flavor full --dart-define=KLARO_SMS=true
    //   • play — Play Store build with NO SMS permissions (passes Google review);
    //            import is manual + paste/forward text. Build with
    //            --flavor play --dart-define=KLARO_SMS=false
    // Same applicationId — they're alternatives, not co-installable.
    flavorDimensions += "dist"
    productFlavors {
        create("full") { dimension = "dist" }
        create("play") { dimension = "dist" }
    }

    signingConfigs {
        create("release") {
            if (keystorePropertiesFile.exists()) {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                // Fallback so `flutter run --release` still works without the keystore.
                signingConfigs.getByName("debug")
            }
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // Backport of newer Java APIs for older Android (needed for desugaring above).
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

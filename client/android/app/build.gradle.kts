plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.muyu.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.muyu.app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    val releaseStorePath = System.getenv("ANDROID_KEYSTORE_PATH")?.takeIf(String::isNotBlank)
    val releaseStorePassword = System.getenv("ANDROID_KEYSTORE_PASSWORD")?.takeIf(String::isNotBlank)
    val releaseKeyAlias = System.getenv("ANDROID_KEY_ALIAS")?.takeIf(String::isNotBlank)
    val releaseKeyPassword = System.getenv("ANDROID_KEY_PASSWORD")?.takeIf(String::isNotBlank)
    val releaseSigningReady = listOf(
        releaseStorePath,
        releaseStorePassword,
        releaseKeyAlias,
        releaseKeyPassword,
    ).all { it != null }
    val releaseSigningConfig = if (releaseSigningReady) {
        signingConfigs.create("release") {
            storeFile = file(releaseStorePath!!)
            storePassword = releaseStorePassword
            keyAlias = releaseKeyAlias
            keyPassword = releaseKeyPassword
        }
    } else {
        null
    }

    buildTypes {
        release {
            // Release artifacts must never silently fall back to the debug key.
            signingConfig = releaseSigningConfig
        }
    }

    // Keep local debug builds usable without credentials, but fail a requested
    // release build before Gradle can produce an unsigned or debug-signed APK.
    gradle.taskGraph.whenReady {
        if (!releaseSigningReady && allTasks.any { it.name.contains("Release", ignoreCase = true) }) {
            throw GradleException(
                "Release Android builds require ANDROID_KEYSTORE_PATH, " +
                    "ANDROID_KEYSTORE_PASSWORD, ANDROID_KEY_ALIAS, and ANDROID_KEY_PASSWORD"
            )
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

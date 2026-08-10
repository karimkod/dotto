import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing credentials. android/key.properties is gitignored and holds
// the store/key passwords plus an absolute path to the keystore, so no secret
// and no keystore ever enters version control. When the file is absent — on a
// fresh clone, or in CI without the secret — the release build falls back to
// debug keys so `flutter run --release` still works locally.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val hasReleaseSigning = keystorePropertiesFile.exists()
if (hasReleaseSigning) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.karimkod.dotto"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // The Play Store listing's package name. It can never be changed once an
        // app is published, so it is set deliberately rather than left as the
        // scaffold's placeholder.
        applicationId = "com.karimkod.dotto"
        // Follows the Flutter SDK's own floor rather than a hardcoded number, so
        // it cannot fall behind what the toolchain actually supports. Flutter's
        // floor is >= 21, which is the minimum this app targets.
        minSdk = flutter.minSdkVersion
        // Tracks the Flutter SDK's current target, which Play requires to stay
        // recent — pinning a number here would silently go stale.
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            // Real upload key when key.properties is present; debug keys otherwise
            // so a clone without the secret can still build and run.
            signingConfig = if (hasReleaseSigning) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

flutter {
    source = "../.."
}

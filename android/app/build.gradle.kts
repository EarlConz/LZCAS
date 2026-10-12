import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    // Push notifications. google-services.json lists both package names
    // (com.lzcas.app and com.lzcas.app.staging), so it serves both flavors.
    id("com.google.gms.google-services")
}

// Release signing credentials — android/key.properties (NOT committed).
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.example.lzcas"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        applicationId = "com.lzcas.app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // Default label; overridden per flavor below so the two builds are
        // distinguishable on the launcher.
        manifestPlaceholders["appLabel"] = "GUTVita"
    }

    // ── Build flavors ────────────────────────────────────────────────
    // "prod" keeps the original applicationId so EXISTING installs keep
    // updating normally. "staging" gets a suffixed id, which is what lets
    // Android treat it as a separate app — both can be installed on the same
    // phone, with separate data, and neither overwrites the other.
    //
    // Build with:  flutter build apk --flavor staging --dart-define=APP_FLAVOR=staging
    flavorDimensions += "env"
    productFlavors {
        create("prod") {
            dimension = "env"
            // No suffix — this IS the production identity.
        }
        create("staging") {
            dimension = "env"
            applicationIdSuffix = ".staging"      // com.lzcas.app.staging
            versionNameSuffix = "-staging"
            manifestPlaceholders["appLabel"] = "GUTVita Staging"
        }
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
            // Signed with the release keystore when key.properties exists;
            // falls back to debug signing so dev machines can still build.
            signingConfig = if (keystorePropertiesFile.exists()) {
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

// Firebase Cloud Messaging, used directly from MainActivity.kt rather than
// through the FlutterFire plugins: those also build for Windows, where they
// download the Firebase C++ SDK on every clean build, and Windows cannot
// receive these pushes anyway. Android shows a push itself when the app is
// closed, so the Dart side only needs the token.
dependencies {
    implementation(platform("com.google.firebase:firebase-bom:33.7.0"))
    implementation("com.google.firebase:firebase-messaging")
}

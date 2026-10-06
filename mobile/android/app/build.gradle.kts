import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("com.google.gms.google-services")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Resolves the Google Maps key without baking it into the repository.
// Order: local.properties -> MAPS_API_KEY env var -> empty.
val mapsApiKey: String = run {
    val props = Properties()
    val f = rootProject.file("local.properties")
    if (f.exists()) FileInputStream(f).use { props.load(it) }
    props.getProperty("MAPS_API_KEY")
        ?: System.getenv("MAPS_API_KEY")
        ?: ""
}

android {
    namespace = "com.pargig.app"
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
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.pargig.app"

        // Google Maps key, injected into AndroidManifest as ${MAPS_API_KEY}.
        //
        // Read from local.properties (gitignored) or the MAPS_API_KEY
        // environment variable, never committed: a key in source control is
        // a key someone else can bill you for. Falls back to an empty
        // string so a checkout without one still compiles — the map tiles
        // just come up blank instead of failing the build.
        manifestPlaceholders["MAPS_API_KEY"] = mapsApiKey
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}

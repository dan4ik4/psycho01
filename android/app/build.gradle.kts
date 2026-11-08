import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val releaseSigningProperties = Properties().apply {
    val propertiesFile = rootProject.file("key.properties")
    if (propertiesFile.exists()) {
        propertiesFile.inputStream().use { load(it) }
    }
}

val releaseBuildRequested = gradle.startParameter.taskNames.any {
    it.contains("release", ignoreCase = true)
}

if (releaseBuildRequested) {
    val configuredApplicationId = providers.gradleProperty("oakleApplicationId")
        .orElse("com.example.god_save_this_shit_app").get()
    val keystorePath = releaseSigningProperties.getProperty("storeFile")
    val keystoreExists = keystorePath != null && rootProject.file(keystorePath).exists()
    val hasSigningValues = listOf("storePassword", "keyAlias", "keyPassword")
        .all { !releaseSigningProperties.getProperty(it).isNullOrBlank() }

    check(!configuredApplicationId.startsWith("com.example.")) {
        "Before a release build, set the permanent unique oakleApplicationId in android/gradle.properties."
    }
    check(keystoreExists && hasSigningValues) {
        "Before a release build, create android/key.properties and configure your private upload keystore."
    }
}
android {
    namespace = providers.gradleProperty("oakleApplicationId")
        .orElse("com.example.god_save_this_shit_app").get()
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
        // Set oakleApplicationId in android/gradle.properties before release.
        applicationId = providers.gradleProperty("oakleApplicationId")
            .orElse("com.example.god_save_this_shit_app").get()
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        //ndkVersion '29.0.14033849'
    }

    signingConfigs {
        create("release") {
            storeFile = releaseSigningProperties.getProperty("storeFile")?.let { rootProject.file(it) }
            storePassword = releaseSigningProperties.getProperty("storePassword")
            keyAlias = releaseSigningProperties.getProperty("keyAlias")
            keyPassword = releaseSigningProperties.getProperty("keyPassword")
        }
    }
    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
        }
    }
}

flutter {
    source = "../.."
}

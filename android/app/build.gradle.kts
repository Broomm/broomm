import java.util.Properties

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val broommSigningFile = rootProject.file("key.properties")
val broommSigning = Properties().apply {
    if (broommSigningFile.exists()) broommSigningFile.reader(Charsets.UTF_8).use { load(it) }
}

android {
    namespace = "app.broomm.broomm"
    compileSdk = flutter.compileSdkVersion
    // Match the pre-provisioned/project-local CI SDK; never auto-install globally.
    ndkVersion = "29.0.14206865"
    buildToolsVersion = "36.1.0"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "app.broomm.broomm"
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

    signingConfigs {
        if (broommSigningFile.exists()) {
            create("broommRelease") {
                storeFile = file(requireNotNull(broommSigning.getProperty("storeFile")))
                storePassword = requireNotNull(broommSigning.getProperty("storePassword"))
                keyAlias = requireNotNull(broommSigning.getProperty("keyAlias"))
                keyPassword = requireNotNull(broommSigning.getProperty("keyPassword"))
            }
        }
    }

    buildTypes {
        release {
            // PR/local builds retain debug signing. The publisher requires secrets.
            signingConfig = signingConfigs.getByName(
                if (broommSigningFile.exists()) "broommRelease" else "debug"
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

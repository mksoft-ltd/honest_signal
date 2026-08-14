import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// House release-signing pattern: a per-app keystore described by a git-ignored
// android/key.properties. When it is absent (a fresh clone, or CI doing a
// compile check) the release build falls back to debug signing so the build
// still runs — it just cannot be uploaded.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val hasReleaseKeystore = keystorePropertiesFile.exists()
if (hasReleaseKeystore) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.froggyeye.honestsignal"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.froggyeye.honestsignal"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseKeystore) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = keystoreProperties["storeFile"]?.let { file(it) }
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasReleaseKeystore) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }
}

dependencies {
    // Pinned because the notification code calls NotificationCompat APIs that
    // only exist from 1.17 (setRequestPromotedOngoing, setShortCriticalText,
    // canPostPromotedNotifications). Without this the runtime classpath
    // resolved 1.17.0 through a transitive constraint while the *compile*
    // classpath stayed on 1.13.1, so the calls failed to compile even though
    // the library that ships in the APK has them.
    implementation("androidx.core:core-ktx:1.17.0")

    // JVM unit tests for the parts of the Kotlin side that are pure logic —
    // currently IndicatorIcons, whose theme/level/contrast mapping no Dart test
    // can reach. `flutter test` does not compile android/**, so without this
    // the mapping could be severed with the whole Dart suite green.
    //   cd android && ./gradlew :app:testDebugUnitTest
    testImplementation("junit:junit:4.13.2")
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

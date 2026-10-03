import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// -----------------------------------------------------------------------------
// Release signing (SA-AND-001)
//
// Release builds are signed ONLY with the LiveDrop upload/release key. There is
// deliberately no fallback to the debug key: the first signed APK fixes the
// signing identity for every install, so a debug-signed "release" can never be
// upgraded in place by a properly signed one.
//
// Source of the signing values, in order:
//   1. seller-app/android/key.properties (gitignored) with the keys
//        storeFile=/absolute/path/to/upload-keystore.jks   (relative = relative to seller-app/android)
//        storePassword=...
//        keyAlias=...
//        keyPassword=...
//   2. Environment variables
//        LIVEDROP_KEYSTORE_PATH, LIVEDROP_KEYSTORE_PASSWORD,
//        LIVEDROP_KEY_ALIAS, LIVEDROP_KEY_PASSWORD
//
// When neither is complete, any release assemble/bundle/install task fails
// before it runs (checked on the task graph), so debug builds, `flutter run`
// in debug mode and `flutter test` are unaffected.
// See docs/ops/android-release-signing.md.
// -----------------------------------------------------------------------------

data class ReleaseSigning(
    val source: String,
    val storeFile: File?,
    val storePassword: String?,
    val keyAlias: String?,
    val keyPassword: String?,
) {
    fun problems(): List<String> {
        val problems = mutableListOf<String>()
        if (storeFile == null) problems += "storeFile / LIVEDROP_KEYSTORE_PATH is not set"
        else if (!storeFile.isFile) problems += "keystore file does not exist: ${storeFile.path}"
        if (storePassword.isNullOrEmpty()) problems += "storePassword / LIVEDROP_KEYSTORE_PASSWORD is not set"
        if (keyAlias.isNullOrEmpty()) problems += "keyAlias / LIVEDROP_KEY_ALIAS is not set"
        if (keyPassword.isNullOrEmpty()) problems += "keyPassword / LIVEDROP_KEY_PASSWORD is not set"
        return problems
    }
}

val keyPropertiesFile: File = rootProject.file("key.properties")

fun String?.nonBlank(): String? = this?.takeIf { it.isNotBlank() }

val releaseSigning: ReleaseSigning? =
    if (keyPropertiesFile.isFile) {
        val props = Properties()
        keyPropertiesFile.inputStream().use { props.load(it) }
        ReleaseSigning(
            source = "key.properties (${keyPropertiesFile.path})",
            storeFile = props.getProperty("storeFile").nonBlank()?.let { rootProject.file(it.trim()) },
            storePassword = props.getProperty("storePassword").nonBlank(),
            keyAlias = props.getProperty("keyAlias").nonBlank()?.trim(),
            keyPassword = props.getProperty("keyPassword").nonBlank(),
        )
    } else if (System.getenv("LIVEDROP_KEYSTORE_PATH").nonBlank() != null) {
        ReleaseSigning(
            source = "LIVEDROP_* environment variables",
            storeFile = System.getenv("LIVEDROP_KEYSTORE_PATH").nonBlank()?.let { rootProject.file(it.trim()) },
            storePassword = System.getenv("LIVEDROP_KEYSTORE_PASSWORD").nonBlank(),
            keyAlias = System.getenv("LIVEDROP_KEY_ALIAS").nonBlank()?.trim(),
            keyPassword = System.getenv("LIVEDROP_KEY_PASSWORD").nonBlank(),
        )
    } else {
        null
    }

val releaseSigningProblems: List<String> =
    releaseSigning?.problems() ?: listOf("no key.properties file and no LIVEDROP_KEYSTORE_PATH environment variable")

val releaseSigningReady: Boolean = releaseSigningProblems.isEmpty()

android {
    namespace = "store.livedrop.seller_app"
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
        applicationId = "store.livedrop.seller_app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // versionCode/versionName come from pubspec.yaml or from
        // `flutter build ... --build-number=<n> --build-name=<x.y.z>` (CI passes the run number).
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (releaseSigningReady) {
            val signing = releaseSigning!!
            create("release") {
                storeFile = signing.storeFile
                storePassword = signing.storePassword
                keyAlias = signing.keyAlias
                keyPassword = signing.keyPassword
            }
        }
    }

    buildTypes {
        release {
            // Never the debug key. Without a release key the release tasks are
            // refused below (fail fast with instructions).
            signingConfig = if (releaseSigningReady) signingConfigs.getByName("release") else null
        }
    }
}

// Tasks that produce, sign or install a release artifact. If any of them is
// about to run without a complete release signing configuration, stop before
// anything executes.
val releaseSigningTaskNames = setOf(
    "assembleRelease",
    "bundleRelease",
    "installRelease",
    "packageRelease",
    "packageReleaseBundle",
    "signReleaseBundle",
    "validateSigningRelease",
)

gradle.taskGraph.whenReady {
    val wantsRelease = allTasks.any { it.project == project && it.name in releaseSigningTaskNames }
    if (wantsRelease && !releaseSigningReady) {
        throw GradleException(
            buildString {
                appendLine("LiveDrop release signing is not configured, refusing to build a release APK/App Bundle.")
                appendLine("Release builds are never signed with the debug key (SA-AND-001).")
                appendLine("Problems:")
                releaseSigningProblems.forEach { appendLine("  - $it") }
                if (releaseSigning != null) appendLine("Signing source checked: ${releaseSigning.source}")
                appendLine("Configure ONE of:")
                appendLine("  * seller-app/android/key.properties (gitignored) containing storeFile, storePassword, keyAlias, keyPassword")
                appendLine("  * environment variables LIVEDROP_KEYSTORE_PATH, LIVEDROP_KEYSTORE_PASSWORD, LIVEDROP_KEY_ALIAS, LIVEDROP_KEY_PASSWORD")
                appendLine("See docs/ops/android-release-signing.md. Debug builds (flutter build apk --debug) need no key.")
            },
        )
    }
}

flutter {
    source = "../.."
}

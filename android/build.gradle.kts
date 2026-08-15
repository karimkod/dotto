// Declared here, applied in app/build.gradle.kts. Without it google-services.json
// is a file sitting in the source tree that nothing reads: the plugin is what
// turns it into the string resources the native SDKs look up at startup, which
// is why Analytics reported "Missing google_app_id" and switched itself off on
// Android. Firebase still started, because Dart passes DefaultFirebaseOptions to
// initializeApp — but that reaches the Dart plugins only, not the native SDKs.
// Crashlytics is declared the same way and applied beside it. Its job at build
// time is to upload the ProGuard/R8 mapping file and stamp the APK with a build
// id, which is what turns an obfuscated release stack trace into readable
// frames. Without the plugin the SDK still reports crashes — they just arrive
// unsymbolicated, which is a report you cannot act on.
plugins {
    id("com.google.gms.google-services") version "4.4.2" apply false
    id("com.google.firebase.crashlytics") version "3.0.6" apply false
}

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}

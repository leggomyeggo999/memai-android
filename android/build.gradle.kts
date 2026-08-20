allprojects {
    repositories {
        google()
        mavenCentral()
    }

    // home_widget 0.9.1 declares OPEN-ENDED dependency ranges in its own
    // android/build.gradle:
    //
    //     implementation "androidx.glance:glance-appwidget:1.+"
    //     implementation "androidx.work:work-runtime-ktx:2.+"
    //
    // so every build re-resolves against whatever AndroidX published most
    // recently — including alphas and release candidates. That makes the
    // Android build non-reproducible and it has already broken twice:
    //
    //   * glance `1.+`  -> 1.3.0-alpha02, which wants compileSdk 37 / AGP 9.1.
    //   * work  `2.+`   -> 2.12.0-rc01, which is compiled for JVM target 11.
    //     home_widget itself sets `jvmTarget = "1.8"`, so :home_widget's
    //     Kotlin compile fails with "Cannot inline bytecode built with JVM
    //     target 11 into bytecode that is being built with JVM target 1.8".
    //
    // These forces MUST live here, in allprojects, not in app/build.gradle.kts:
    // a resolutionStrategy declared in the :app module only governs :app's own
    // configurations, so it never reached :home_widget's compile classpath.
    // Pinned to the current STABLE releases; bump deliberately, never by range.
    configurations.configureEach {
        resolutionStrategy {
            force("androidx.glance:glance-appwidget:1.1.1")
            force("androidx.work:work-runtime:2.10.0")
            force("androidx.work:work-runtime-ktx:2.10.0")
        }
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

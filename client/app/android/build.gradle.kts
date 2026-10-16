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

// CameraX 1.5 exposes CallbackToFutureAdapter in a public signature but the
// Flutter CameraX plugin does not declare that artifact on its Java classpath.
// Add Google's stable artifact to the plugin module until its own Gradle
// dependencies include it.
subprojects {
    if (name == "camera_android_camerax") {
        pluginManager.withPlugin("com.android.library") {
            dependencies.add("implementation", "androidx.concurrent:concurrent-futures:1.3.0")
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}

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
    project.plugins.withId("com.android.library") {
        project.extensions.findByType(com.android.build.gradle.BaseExtension::class.java)?.apply {
            compileOptions {
                sourceCompatibility = JavaVersion.VERSION_17
                targetCompatibility = JavaVersion.VERSION_17
            }
        }
        // Ensure Kotlin plugin is applied for all library subprojects
        // (file_picker v11 skips it when AGP >= 9, but builtInKotlin=false)
        if (!project.plugins.hasPlugin("org.jetbrains.kotlin.android")) {
            project.apply(plugin = "org.jetbrains.kotlin.android")
        }
    }
    // Set Kotlin JVM target to 17 for all subprojects to match Java sourceCompatibility
    project.plugins.withId("org.jetbrains.kotlin.android") {
        project.extensions.findByType(org.jetbrains.kotlin.gradle.dsl.KotlinAndroidProjectExtension::class.java)?.apply {
            compilerOptions {
                jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}

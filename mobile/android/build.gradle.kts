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

    // Namespace fallback for legacy Flutter plugins (e.g. `record 4.4.4`)
    // that still declare `package="…"` in their AndroidManifest.xml
    // instead of the modern `namespace = "…"` in build.gradle. AGP 8+
    // rejects the legacy form with "Namespace not specified."
    // Walks every subproject after evaluation, checks if an
    // `android { … }` extension exists with no namespace set, and
    // writes `project.group` into it via reflection so it works with
    // both the Groovy and Kotlin-DSL android extensions.
    // IMPORTANT: this MUST be registered before the
    // `evaluationDependsOn(":app")` block below, otherwise the
    // subprojects are already evaluated by the time we get here and
    // Gradle throws "Cannot run Project.afterEvaluate when already
    // evaluated".
    afterEvaluate {
        val androidExt = extensions.findByName("android")
        if (androidExt != null) {
            val getter = androidExt.javaClass.methods.firstOrNull {
                it.name == "getNamespace" && it.parameterCount == 0
            }
            val setter = androidExt.javaClass.methods.firstOrNull {
                it.name == "setNamespace" && it.parameterCount == 1
            }
            if (getter != null && setter != null
                && getter.invoke(androidExt) == null) {
                setter.invoke(androidExt, project.group.toString())
            }
        }
    }
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}

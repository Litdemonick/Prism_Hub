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

// Workaround AGP 8+/9: algunos plugins antiguos (p. ej. isar_flutter_libs
// 3.1.0+1) no declaran `namespace` en su build.gradle, requerido por las
// versiones nuevas del Android Gradle Plugin. Se lo inyectamos en cuanto el
// plugin de Android se aplica — antes de que AGP cree las variantes. Vía
// reflexión para no necesitar las clases de AGP en el classpath del build raíz.
// Debe ir ANTES del bloque evaluationDependsOn(":app"), que dispara la
// evaluación temprana de los plugins.
subprojects {
    val injectNamespace = {
        val android = extensions.findByName("android")
        if (android != null) {
            try {
                val current =
                    android.javaClass.getMethod("getNamespace").invoke(android) as String?
                if (current.isNullOrBlank()) {
                    val ns = project.group.toString().ifBlank {
                        "com.prismhub.${project.name.replace(Regex("[^A-Za-z0-9_]"), "_")}"
                    }
                    android.javaClass.getMethod("setNamespace", String::class.java)
                        .invoke(android, ns)
                    logger.lifecycle("Namespace inyectado para ${project.name}: $ns")
                }
            } catch (_: Exception) {
                // La extensión no expone la API de namespace — ignorar.
            }
        }
    }
    plugins.withId("com.android.library") { injectNamespace() }
    plugins.withId("com.android.application") { injectNamespace() }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}

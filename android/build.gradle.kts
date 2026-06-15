allprojects {
    repositories {
        // Repo local vendorizado: contiene la nativa QuickJS de flutter_js
        // (fastdev-jsruntimes-quickjs) que normalmente vive en jitpack.io. Al
        // ponerlo PRIMERO, Gradle la resuelve del disco y nunca consulta jitpack
        // → el build no depende de que jitpack esté disponible.
        maven { url = uri("${rootProject.projectDir}/offline-repo") }
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

// Workaround: unificar el JVM target de Java y Kotlin en todos los módulos.
// Plugins antiguos (flutter_js) declaran Java 11 y Kotlin 1.8 → error
// "Inconsistent JVM-target compatibility". Forzamos 17 (igual que la app).
// Java se setea vía la extensión `android` en afterEvaluate para ganarle al
// compileOptions{11} que declara flutter_js en su propio build.gradle.
subprojects {
    afterEvaluate {
        (extensions.findByName("android") as? com.android.build.gradle.BaseExtension)
            ?.apply {
                compileOptions {
                    sourceCompatibility = JavaVersion.VERSION_17
                    targetCompatibility = JavaVersion.VERSION_17
                }
                // Subir compileSdk de plugins viejos (isar usa 30) → 36,
                // requerido por dependencias androidx nuevas.
                val csv = compileSdkVersion?.removePrefix("android-")?.toIntOrNull()
                if (csv != null && csv < 35) {
                    compileSdkVersion(36)
                }
            }
    }
    tasks.withType(org.jetbrains.kotlin.gradle.tasks.KotlinCompile::class.java)
        .configureEach {
            compilerOptions {
                jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
            }
        }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}

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

// Fix "Inconsistent JVM Target Compatibility" — flutter_nfc_kit khai báo Java
// sourceCompatibility/targetCompatibility = 11 nhưng không set jvmTarget cho Kotlin,
// khiến Kotlin compiler suy ra JVM target theo JDK đang chạy (ở đây là 21) và lệch với
// phần Java (11). Chỉ áp dụng cho module flutter_nfc_kit — không ép jvmTarget toàn cục
// vì các plugin khác dùng mặc định Java 17 của Flutter Gradle plugin sẽ vỡ nếu bị ép về 11.
//
// Dùng gradle.beforeProject (không phải subprojects { afterEvaluate {...} }) vì với
// AGP/Gradle hiện tại, ":flutter_nfc_kit" (subproject được settings.gradle.kts include
// động qua flutter-plugin-loader) có thể đã evaluate xong trước khi block subprojects{}
// phía trên chạy tới nó, khiến afterEvaluate() ném "project already evaluated".
// gradle.beforeProject đăng ký hook TRƯỚC khi project đó bắt đầu evaluate nên luôn an toàn.
// flutter_nfc_kit 3.4.2 cũng tự hard-code compileSdkVersion 33 trong
// android/build.gradle của chính nó — quá cũ so với compileSdk mà các
// androidx transitive dependency hiện tại (activity/fragment/lifecycle...)
// yêu cầu (>=34), khiến AGP hiện đại fail ở task checkDebugAarMetadata.
// Ép compileSdk theo đúng bản Flutter Gradle plugin đang dùng cho module này —
// chỉ flutter_nfc_kit, không đụng tới compileSdk của :app hay plugin khác.
gradle.beforeProject {
    if (name == "flutter_nfc_kit") {
        afterEvaluate {
            extensions.findByType(com.android.build.gradle.LibraryExtension::class.java)
                ?.compileSdk = 36
            tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
                compilerOptions {
                    jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_11)
                }
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}

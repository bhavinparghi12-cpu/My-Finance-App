plugins {
    id("com.android.application")
    // Kotlin Android પ્લગઇન ઉમેરવું જરૂરી છે
    id("kotlin-android")
    // Flutter Gradle પ્લગઇન Android અને Kotlin પછી જ હોવું જોઈએ
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.my_finance_app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.example.my_finance_app"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // રીલીઝ બિલ્ડ માટે યોગ્ય સાઇનિંગ કોન્ફિગ
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
    }
}

flutter {
    source = "../.."
}

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.cv_training_app"
    compileSdk = 34
    
    defaultConfig {
        applicationId = "com.example.cv_training_app"
        minSdk = flutter.minSdkVersion
        targetSdk = 34
        versionCode = 1
        versionName = "1.0"
    }
    
    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
        }
    }
    
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_1_8
        targetCompatibility = JavaVersion.VERSION_1_8
    }
    
    kotlinOptions {
        jvmTarget = "1.8"
    }
}

dependencies {
    implementation("org.jetbrains.kotlin:kotlin-stdlib-jdk7")
    
    // TensorFlow Lite - INI YANG PENTING
    implementation("org.tensorflow:tensorflow-lite:2.12.0")
    implementation("org.tensorflow:tensorflow-lite-support:0.4.3")
    implementation("org.tensorflow:tensorflow-lite-select-tf-ops:2.12.0")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.7.3")
}

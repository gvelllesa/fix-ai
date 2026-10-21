# Flutter ProGuard / R8 Rules
-keepattributes *Annotation*,Signature,InnerClasses,EnclosingMethod

# Flutter Engine & Embeddings
-keep class io.flutter.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.embedding.** { *; }
-keep class io.flutter.view.** { *; }

# Foreground Task & Connectivity
-keep class com.pravera.flutter_foreground_task.** { *; }
-keep class androidx.concurrent.futures.** { *; }

# Keep Native MethodChannel callbacks
-keepclassmembers class * extends io.flutter.embedding.android.FlutterActivity {
    *;
}

# Preserve Native and JNI methods
-keepclasseswithmembernames class * {
    native <methods>;
}

# Preserve Serialization & Annotations
-keepclassmembers class * {
    @androidx.annotation.Keep <fields>;
    @androidx.annotation.Keep <methods>;
}

# Keep Application & Native USB FTDI Activity
-keep class com.example.ai_car_diagnostics.** { *; }

# Keep AndroidX Room, WorkManager, Startup & Concurrent
-keep class * extends androidx.room.RoomDatabase { *; }
-keep @androidx.room.Database class * { *; }
-keep class * implements androidx.startup.Initializer { *; }
-keep class androidx.work.** { *; }
-keep class androidx.room.** { *; }
-keep class androidx.startup.** { *; }

# Suppress optional Play Core deferred components & ML Kit optional language models
-dontwarn com.google.android.play.core.**
-dontwarn com.google.firebase.iid.FirebaseInstanceId
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**



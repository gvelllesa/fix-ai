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

# Obfuscate proprietary algorithm implementations and business logic
-repackageclasses 'com.example.ai_car_diagnostics.obfuscated'
-allowaccessmodification

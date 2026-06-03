# Flutter / Dart
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.**  { *; }
-keep class io.flutter.plugins.**  { *; }
-dontwarn io.flutter.embedding.**

# Dio (HTTP client) - reflection used for JSON
-keep class com.dio.** { *; }
-dontwarn com.dio.**

# Workmanager
-keep class * extends androidx.work.Worker
-keep class * extends androidx.work.InputMerger
-keep class androidx.work.** { *; }

# Background service
-keep class id.flutter.flutter_background_service.** { *; }
-keep class * extends android.app.Service

# Phone state / call log
-keep class sk.fourq.** { *; }
-keep class kr.co.bootpay.** { *; }

# Alarm Manager
-keep class dev.fluttercommunity.plus.androidalarmmanager.** { *; }

# Local notifications
-keep class com.dexterous.** { *; }

# Notification icon (don't strip)
-keep class **.R$* { *; }

# Keep all model classes (UserModel, etc.) for JSON serialization
-keep class com.example.glcalls.** { *; }

# Keep entry points for background tasks
-keepclassmembers class * {
    @androidx.work.Worker public *;
}
-keepclasseswithmembernames class * {
    @androidx.annotation.Keep <methods>;
}

# Pragma vm:entry-point used by background isolates
-keep @androidx.annotation.Keep class * { *; }
-keepclasseswithmembers class * {
    @androidx.annotation.Keep <methods>;
}

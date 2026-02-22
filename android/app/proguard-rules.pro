# Flutter / Dart
-keep class io.flutter.** { *; }
-dontwarn io.flutter.embedding.**

# Firebase
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.firebase.**

# Kotlin
-keep class kotlin.** { *; }
-dontwarn kotlin.**

# Cryptography (BouncyCastle used by cryptography package)
-keep class org.bouncycastle.** { *; }
-dontwarn org.bouncycastle.**

# Socket.io
-keep class io.socket.** { *; }
-dontwarn io.socket.**

# Our app
-keep class com.securechat.** { *; }

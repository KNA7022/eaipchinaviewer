-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-keep class com.google.firebase.** { *; }

# 保持 Flutter WebView 相关类
-keep class com.pichillilorenzo.flutter_inappwebview.** { *; }
-keep class android.webkit.** { *; }

# 不混淆某些包下的所有类
-dontwarn io.flutter.embedding.**
-dontwarn android.webkit.WebView
-dontwarn android.webkit.WebViewClient

# 保持 native 方法
-keepclasseswithmembernames class * {
    native <methods>;
}

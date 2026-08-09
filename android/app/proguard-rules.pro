# The foreground service, overlay service and boot receiver are only ever
# referenced from AndroidManifest.xml. R8 keeps manifest-declared components,
# but the background Flutter engine is started by *name* from
# HonestSignalService, so keep the app's own components explicitly rather than
# relying on that inference.
-keep class com.froggyeye.honestsignal.** { *; }

# Flutter's embedding reflects over its plugin registrant.
-keep class io.flutter.embedding.** { *; }
-keep class io.flutter.plugins.** { *; }

# Google Play Billing (in_app_purchase) — the library's own consumer rules
# cover most of it; the proto classes it serialises are the exception.
-keep class com.android.vending.billing.** { *; }
-dontwarn com.google.android.play.core.**

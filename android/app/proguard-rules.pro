# flutter_local_notifications uses Gson reflection on generic types; R8 strips
# the generic signatures without these (notifications crash in release builds).
-keep class com.dexterous.** { *; }
-keep class com.google.gson.reflect.TypeToken { *; }
-keep class * extends com.google.gson.reflect.TypeToken
-keepattributes Signature

# another_telephony background SMS receiver is invoked reflectively by the OS.
-keep class com.shounakmulay.telephony.** { *; }

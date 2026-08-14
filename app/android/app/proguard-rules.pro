# R8 rules for the release build.
#
# Flutter's own engine classes are kept by the plugin's consumer rules; these
# cover the plugins this app uses that reflect at runtime.

# speech_to_text talks to Android's SpeechRecognizer through a callback
# interface that R8 cannot see being implemented.
-keep class android.speech.** { *; }
-dontwarn android.speech.**

# Play Core is referenced by Flutter's deferred-components support, which this
# app does not use. Without this, R8 fails on the missing classes.
-dontwarn com.google.android.play.core.**

# Keep annotations used for JSON round-tripping in the Supabase client.
-keepattributes *Annotation*, Signature, InnerClasses, EnclosingMethod

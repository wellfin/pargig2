# Razorpay checkout.
#
# The SDK calls back into the app by reflection, so its classes and the
# onPayment* handlers must survive shrinking. Without these, a minified
# release build opens the payment sheet and then crashes on the way
# back — a failure that only ever shows up in a release APK, never in
# debug, which is exactly the kind that reaches a user first.
-keepattributes *Annotation*
-dontwarn com.razorpay.**
-keep class com.razorpay.** { *; }
-optimizations !method/inlining/
-keepclasseswithmembers class * {
  public void onPayment*(...);
}

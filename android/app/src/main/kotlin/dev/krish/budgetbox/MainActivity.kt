package dev.krish.budgetbox

import io.flutter.embedding.android.FlutterFragmentActivity

// FlutterFragmentActivity, not FlutterActivity: local_auth's biometric prompt
// can only attach to a FragmentActivity — on the plain one, the lock screen's
// fingerprint/face path dies quietly.
class MainActivity : FlutterFragmentActivity()

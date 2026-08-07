package com.corporacionronceros.panaderia_app

import io.flutter.embedding.android.FlutterFragmentActivity

// FlutterFragmentActivity (en vez de FlutterActivity) es requerido por
// local_auth, que usa androidx.biometric.BiometricPrompt internamente.
class MainActivity : FlutterFragmentActivity()

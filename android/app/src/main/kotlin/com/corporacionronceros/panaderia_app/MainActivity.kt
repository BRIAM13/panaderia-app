package com.corporacionronceros.panaderia_app

import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// FlutterFragmentActivity (en vez de FlutterActivity) es requerido por
// local_auth, que usa androidx.biometric.BiometricPrompt internamente.
class MainActivity : FlutterFragmentActivity() {
    // Canal mínimo, sin depender de ningún paquete de pub.dev: tras entregar
    // el APK descargado al instalador del sistema (ver
    // ActualizacionRequeridaPage), la app necesita cerrarse de una forma que
    // además saque su tarea de "Recientes". Ni exit(0) ni
    // SystemNavigator.pop() (que solo llama a Activity.finish()) lo logran
    // — Android deja ahí cualquier app cerrada normalmente a propósito, para
    // poder "volver" a ella. finishAndRemoveTask() es el único método que
    // de verdad la saca de la lista.
    private val canalCierre = "corporacionronceros/cierre_app"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, canalCierre)
            .setMethodCallHandler { call, result ->
                if (call.method == "finishAndRemoveTask") {
                    finishAndRemoveTask()
                    result.success(null)
                } else {
                    result.notImplemented()
                }
            }
    }
}

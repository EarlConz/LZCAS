package com.example.lzcas

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.pm.PackageManager
import android.os.Build
import com.google.firebase.messaging.FirebaseMessaging
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Push notifications, bridged to Dart on the "gutvita/push" channel
 * (lib/services/push_service.dart).
 *
 * Firebase is used directly here instead of through the FlutterFire plugins,
 * which would also build for Windows (see android/app/build.gradle.kts).
 * While the app is closed, Firebase shows each push itself on the
 * "deliveries" channel created below; while it is open, the in-app alerts
 * cover it and the push is not shown twice.
 */
class MainActivity : FlutterActivity() {
    private var pendingPermission: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        createDeliveriesChannel()

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "gutvita/push")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "requestPermission" -> requestNotificationPermission(result)
                    "getToken" ->
                        FirebaseMessaging.getInstance().token.addOnCompleteListener { task ->
                            if (task.isSuccessful) {
                                result.success(task.result)
                            } else {
                                result.error("token", task.exception?.message, null)
                            }
                        }
                    // Sign-out: this phone stops being reachable at all, even
                    // if the server never hears that it signed out.
                    "deleteToken" ->
                        FirebaseMessaging.getInstance().deleteToken()
                            .addOnCompleteListener { result.success(null) }
                    else -> result.notImplemented()
                }
            }
    }

    /** High importance: a sound and a heads-up banner, not a silent tray entry. */
    private fun createDeliveriesChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Deliveries",
            NotificationManager.IMPORTANCE_HIGH,
        ).apply { description = "New deliveries and order updates" }
        getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
    }

    /** Android 13+ asks; earlier versions allow notifications by default. */
    private fun requestNotificationPermission(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED
        ) {
            result.success(true)
            return
        }
        // A second request while one is showing answers the first as "no".
        pendingPermission?.success(false)
        pendingPermission = result
        requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), PERMISSION_REQUEST)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        // super first: the location plugin receives its own answers through it.
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != PERMISSION_REQUEST) return
        pendingPermission?.success(
            grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED,
        )
        pendingPermission = null
    }

    companion object {
        const val CHANNEL_ID = "deliveries"
        const val PERMISSION_REQUEST = 4201
    }
}

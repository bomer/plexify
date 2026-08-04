package com.jamesotoole.plexify

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// Must extend AudioServiceActivity rather than FlutterActivity. audio_service
// needs to own the activity lifecycle so playback survives the activity being
// destroyed — with a plain FlutterActivity, audio stops the moment the app is
// swiped away or the screen locks.
class MainActivity : AudioServiceActivity() {

    private companion object {
        const val NOTIFICATION_PERMISSION_REQUEST = 1001
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "plexify/app")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    // Back at the root route should minimise, not finish the
                    // activity. Finishing tears down the Flutter engine and
                    // kills playback; moveTaskToBack leaves the foreground
                    // service running so the music keeps going.
                    "moveToBackground" -> {
                        moveTaskToBack(true)
                        result.success(true)
                    }

                    // POST_NOTIFICATIONS is a runtime permission from API 33.
                    // audio_service declares it but never asks, so without this
                    // there is no media notification and therefore no
                    // lock-screen controls.
                    //
                    // Done here rather than via permission_handler: that package
                    // pulls in a Windows implementation that fails to compile
                    // against current MSVC, and we only ever need this on
                    // Android.
                    "requestNotificationPermission" -> {
                        requestNotificationPermission()
                        result.success(true)
                    }

                    else -> result.notImplemented()
                }
            }
    }

    private fun requestNotificationPermission() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return
        val granted = checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED
        if (!granted) {
            requestPermissions(
                arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                NOTIFICATION_PERMISSION_REQUEST,
            )
        }
    }
}

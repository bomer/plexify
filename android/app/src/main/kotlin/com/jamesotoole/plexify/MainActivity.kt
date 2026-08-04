package com.jamesotoole.plexify

import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// Must extend AudioServiceActivity rather than FlutterActivity. audio_service
// needs to own the activity lifecycle so playback survives the activity being
// destroyed — with a plain FlutterActivity, audio stops the moment the app is
// swiped away or the screen locks.
class MainActivity : AudioServiceActivity() {

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
                    else -> result.notImplemented()
                }
            }
    }
}

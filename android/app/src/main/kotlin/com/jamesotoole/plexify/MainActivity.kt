package com.jamesotoole.plexify

import com.ryanheise.audioservice.AudioServiceActivity

// Must extend AudioServiceActivity rather than FlutterActivity. audio_service
// needs to own the activity lifecycle so playback survives the activity being
// destroyed — with a plain FlutterActivity, audio stops the moment the app is
// swiped away or the screen locks.
class MainActivity : AudioServiceActivity()

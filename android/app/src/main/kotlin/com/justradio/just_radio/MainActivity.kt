package com.justradio.just_radio

import android.util.Log
import androidx.media3.common.util.UnstableApi
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

@UnstableApi
class MainActivity : FlutterActivity() {
    companion object {
        private const val TAG = "JustRadioMainActivity"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        Log.d(TAG, "configureFlutterEngine ENTRY")
        // Register our plugin BEFORE super. If GeneratedPluginRegistrant
        // ever throws during attach (e.g., a misbehaving transitive plugin),
        // ours is already wired up.
        try {
            flutterEngine.plugins.add(AudioPlayerPlugin())
            Log.d(TAG, "AudioPlayerPlugin added to registry")
        } catch (t: Throwable) {
            Log.e(TAG, "Failed to add AudioPlayerPlugin", t)
        }
        super.configureFlutterEngine(flutterEngine)
        Log.d(TAG, "configureFlutterEngine EXIT")
    }
}

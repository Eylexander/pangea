package com.eylexander.pangea

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    // The settings screen shows the installed version, the one CI stamps from the release tag.
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "pangea/app").setMethodCallHandler { call, result ->
            if (call.method == "version") {
                result.success(packageManager.getPackageInfo(packageName, 0).versionName)
            } else {
                result.notImplemented()
            }
        }
    }
}

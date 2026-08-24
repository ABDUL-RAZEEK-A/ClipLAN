package com.cliplan.cliplan

import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.content.pm.PackageManager

class MainActivity : FlutterFragmentActivity() {
    private val CHANNEL = "com.cliplan/apkPaths"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "getApkPaths") {
                try {
                    val pm = this@MainActivity.packageManager
                    val packages = pm.getInstalledApplications(PackageManager.GET_META_DATA)
                    val paths = mutableMapOf<String, String>()
                    for (appInfo in packages) {
                        paths[appInfo.packageName] = appInfo.sourceDir
                    }
                    result.success(paths)
                } catch (e: Exception) {
                    result.error("ERROR", e.message, null)
                }
            } else {
                result.notImplemented()
            }
        }
    }
}

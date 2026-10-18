package com.clipland.clipland

import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.content.pm.PackageManager
import android.media.MediaScannerConnection
import android.net.Uri
import java.io.File

class MainActivity : FlutterFragmentActivity() {
    private val CHANNEL = "com.cliplan/apkPaths"
    private val MEDIA_SCANNER_CHANNEL = "com.cliplan/mediaScanner"

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        androidx.core.view.WindowCompat.setDecorFitsSystemWindows(window, false)
        super.onCreate(savedInstanceState)
    }

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

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, MEDIA_SCANNER_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "scanFile" -> {
                    val path = call.argument<String>("path")
                    if (!path.isNullOrEmpty()) {
                        val file = File(path)
                        if (file.exists()) {
                            MediaScannerConnection.scanFile(
                                applicationContext,
                                arrayOf(file.absolutePath),
                                null
                            ) { scannedPath, _ ->
                                try {
                                    val mediaScanIntent = android.content.Intent(android.content.Intent.ACTION_MEDIA_SCANNER_SCAN_FILE)
                                    mediaScanIntent.data = Uri.fromFile(File(scannedPath))
                                    applicationContext.sendBroadcast(mediaScanIntent)
                                } catch (ignored: Exception) {}
                            }
                            result.success(true)
                        } else {
                            result.success(false)
                        }
                    } else {
                        result.error("INVALID_PATH", "Path was null or empty", null)
                    }
                }
                "scanFiles" -> {
                    val paths = call.argument<List<String>>("paths")
                    if (!paths.isNullOrEmpty()) {
                        val validPaths = paths.mapNotNull {
                            val f = File(it)
                            if (f.exists()) f.absolutePath else null
                        }.toTypedArray()

                        if (validPaths.isNotEmpty()) {
                            MediaScannerConnection.scanFile(
                                applicationContext,
                                validPaths,
                                null
                            ) { scannedPath, _ ->
                                try {
                                    val mediaScanIntent = android.content.Intent(android.content.Intent.ACTION_MEDIA_SCANNER_SCAN_FILE)
                                    mediaScanIntent.data = Uri.fromFile(File(scannedPath))
                                    applicationContext.sendBroadcast(mediaScanIntent)
                                } catch (ignored: Exception) {}
                            }
                            result.success(true)
                        } else {
                            result.success(false)
                        }
                    } else {
                        result.success(false)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
}

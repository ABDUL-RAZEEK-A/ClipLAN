package com.clipland.clipland

import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.content.Context
import android.content.pm.PackageManager
import android.media.MediaScannerConnection
import android.net.Uri
import android.net.wifi.WifiManager
import java.io.File

class MainActivity : FlutterFragmentActivity() {
    private val CHANNEL = "com.cliplan/apkPaths"
    private val MEDIA_SCANNER_CHANNEL = "com.cliplan/mediaScanner"
    private val SHARE_INTENT_CHANNEL = "com.cliplan/shareIntent"
    private val NATIVE_PICKER_CHANNEL = "com.cliplan/nativePicker"
    private val PICK_FILES_REQUEST_CODE = 4129
    private var pendingPickerResult: MethodChannel.Result? = null

    private var initialSharedPaths: List<String>? = null
    private var shareMethodChannel: MethodChannel? = null

    private var multicastLock: WifiManager.MulticastLock? = null
    private var wifiLock: WifiManager.WifiLock? = null

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        androidx.core.view.WindowCompat.setDecorFitsSystemWindows(window, false)
        acquireNetworkLocks()
        handleShareIntent(intent, isInitial = true)
        super.onCreate(savedInstanceState)
    }

    override fun onResume() {
        super.onResume()
        acquireNetworkLocks()
    }

    override fun onDestroy() {
        releaseNetworkLocks()
        super.onDestroy()
    }

    private fun acquireNetworkLocks() {
        try {
            val wifiManager = applicationContext.getSystemService(Context.WIFI_SERVICE) as? WifiManager
            if (wifiManager != null) {
                if (multicastLock == null || !multicastLock!!.isHeld) {
                    multicastLock = wifiManager.createMulticastLock("ClipLAN:MulticastLock").apply {
                        setReferenceCounted(true)
                        acquire()
                    }
                }
                if (wifiLock == null || !wifiLock!!.isHeld) {
                    @Suppress("DEPRECATION")
                    wifiLock = wifiManager.createWifiLock(
                        WifiManager.WIFI_MODE_FULL_HIGH_PERF,
                        "ClipLAN:WifiLock"
                    ).apply {
                        setReferenceCounted(true)
                        acquire()
                    }
                }
            }
        } catch (e: Exception) {
            android.util.Log.e("ClipLAN_MainActivity", "Failed to acquire WiFi/Multicast locks", e)
        }
    }

    private fun releaseNetworkLocks() {
        try {
            multicastLock?.let {
                if (it.isHeld) it.release()
            }
            multicastLock = null

            wifiLock?.let {
                if (it.isHeld) it.release()
            }
            wifiLock = null
        } catch (e: Exception) {
            android.util.Log.e("ClipLAN_MainActivity", "Failed to release WiFi/Multicast locks", e)
        }
    }

    override fun onNewIntent(intent: android.content.Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleShareIntent(intent, isInitial = false)
    }

    private fun handleShareIntent(intent: android.content.Intent?, isInitial: Boolean) {
        if (intent == null) return
        val action = intent.action
        if (action == android.content.Intent.ACTION_SEND || action == android.content.Intent.ACTION_SEND_MULTIPLE) {
            val resolvedPaths = mutableListOf<String>()

            if (action == android.content.Intent.ACTION_SEND) {
                val uri = if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.TIRAMISU) {
                    intent.getParcelableExtra(android.content.Intent.EXTRA_STREAM, Uri::class.java)
                } else {
                    @Suppress("DEPRECATION")
                    intent.getParcelableExtra(android.content.Intent.EXTRA_STREAM) as? Uri
                } ?: intent.data

                if (uri != null) {
                    val path = UriUtils.getRealPathFromUri(this, uri)
                    if (path != null && File(path).exists()) {
                        resolvedPaths.add(path)
                    }
                }
            } else if (action == android.content.Intent.ACTION_SEND_MULTIPLE) {
                val uris = if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.TIRAMISU) {
                    intent.getParcelableArrayListExtra(android.content.Intent.EXTRA_STREAM, Uri::class.java)
                } else {
                    @Suppress("DEPRECATION")
                    intent.getParcelableArrayListExtra(android.content.Intent.EXTRA_STREAM)
                }

                if (uris != null) {
                    for (uri in uris) {
                        val path = UriUtils.getRealPathFromUri(this, uri)
                        if (path != null && File(path).exists()) {
                            resolvedPaths.add(path)
                        }
                    }
                }
            }

            if (resolvedPaths.isNotEmpty()) {
                if (isInitial) {
                    initialSharedPaths = resolvedPaths
                }
                shareMethodChannel?.invokeMethod("onSharedFiles", resolvedPaths)
            }
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val shareChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SHARE_INTENT_CHANNEL)
        shareMethodChannel = shareChannel
        shareChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "getInitialSharedFiles" -> {
                    val paths = initialSharedPaths
                    initialSharedPaths = null
                    result.success(paths ?: emptyList<String>())
                }
                else -> result.notImplemented()
            }
        }

        initialSharedPaths?.let { paths ->
            shareChannel.invokeMethod("onSharedFiles", paths)
        }

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

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, NATIVE_PICKER_CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "pickFiles") {
                val allowMultiple = call.argument<Boolean>("allowMultiple") ?: true
                val type = call.argument<String>("type") ?: "any"

                pendingPickerResult?.error("CANCELLED", "New pick request started", null)
                pendingPickerResult = result

                try {
                    val intent = android.content.Intent(android.content.Intent.ACTION_OPEN_DOCUMENT).apply {
                        addCategory(android.content.Intent.CATEGORY_OPENABLE)
                        if (type == "media" || type == "image_video") {
                            this.type = "*/*"
                            putExtra(android.content.Intent.EXTRA_MIME_TYPES, arrayOf("image/*", "video/*"))
                        } else if (type == "image") {
                            this.type = "image/*"
                        } else if (type == "video") {
                            this.type = "video/*"
                        } else {
                            this.type = "*/*"
                        }
                        putExtra(android.content.Intent.EXTRA_ALLOW_MULTIPLE, allowMultiple)
                        addFlags(android.content.Intent.FLAG_GRANT_READ_URI_PERMISSION or android.content.Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
                    }
                    startActivityForResult(intent, PICK_FILES_REQUEST_CODE)
                } catch (e: Exception) {
                    try {
                        val intent = android.content.Intent(android.content.Intent.ACTION_GET_CONTENT).apply {
                            if (type == "media" || type == "image_video") {
                                this.type = "*/*"
                                putExtra(android.content.Intent.EXTRA_MIME_TYPES, arrayOf("image/*", "video/*"))
                            } else if (type == "image") {
                                this.type = "image/*"
                            } else if (type == "video") {
                                this.type = "video/*"
                            } else {
                                this.type = "*/*"
                            }
                            putExtra(android.content.Intent.EXTRA_ALLOW_MULTIPLE, allowMultiple)
                        }
                        startActivityForResult(intent, PICK_FILES_REQUEST_CODE)
                    } catch (err: Exception) {
                        pendingPickerResult = null
                        result.error("PICKER_ERROR", err.message, null)
                    }
                }
            } else {
                result.notImplemented()
            }
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: android.content.Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == PICK_FILES_REQUEST_CODE) {
            val pending = pendingPickerResult
            pendingPickerResult = null
            if (pending == null) return

            if (resultCode != android.app.Activity.RESULT_OK || data == null) {
                pending.success(emptyList<Map<String, Any>>())
                return
            }

            val uris = mutableListOf<Uri>()
            data.clipData?.let { clipData ->
                for (i in 0 until clipData.itemCount) {
                    val itemUri = clipData.getItemAt(i).uri
                    if (itemUri != null) uris.add(itemUri)
                }
            }
            if (uris.isEmpty() && data.data != null) {
                uris.add(data.data!!)
            }

            val resolved = mutableListOf<Map<String, Any>>()
            for (uri in uris) {
                try {
                    try {
                        contentResolver.takePersistableUriPermission(
                            uri,
                            android.content.Intent.FLAG_GRANT_READ_URI_PERMISSION
                        )
                    } catch (ignored: Exception) {}

                    val path = UriUtils.getRealPathFromUri(this, uri)
                    if (path != null && File(path).exists()) {
                        val file = File(path)
                        resolved.add(mapOf(
                            "path" to path,
                            "name" to file.name,
                            "size" to file.length()
                        ))
                    } else {
                        var name: String? = null
                        var size: Long = -1L
                        contentResolver.query(uri, arrayOf(android.provider.OpenableColumns.DISPLAY_NAME, android.provider.OpenableColumns.SIZE), null, null, null)?.use { c ->
                            if (c.moveToFirst()) {
                                val nIdx = c.getColumnIndex(android.provider.OpenableColumns.DISPLAY_NAME)
                                val sIdx = c.getColumnIndex(android.provider.OpenableColumns.SIZE)
                                if (nIdx != -1) name = c.getString(nIdx)
                                if (sIdx != -1) size = c.getLong(sIdx)
                            }
                        }
                        val fallbackFile = File(cacheDir, name ?: "picked_${System.currentTimeMillis()}")
                        contentResolver.openInputStream(uri)?.use { input ->
                            fallbackFile.outputStream().use { output ->
                                input.copyTo(output)
                            }
                        }
                        if (fallbackFile.exists()) {
                            resolved.add(mapOf(
                                "path" to fallbackFile.absolutePath,
                                "name" to fallbackFile.name,
                                "size" to fallbackFile.length()
                            ))
                        }
                    }
                } catch (e: Exception) {
                    android.util.Log.e("ClipLAN_Picker", "Error resolving picked URI: $uri", e)
                }
            }
            pending.success(resolved)
        }
    }
}

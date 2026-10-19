package com.clipland.clipland

import android.content.ContentResolver
import android.content.ContentUris
import android.content.Context
import android.net.Uri
import android.os.Environment
import android.provider.DocumentsContract
import android.provider.MediaStore
import java.io.File

/**
 * High-performance zero-copy URI resolver for Android.
 * Resolves Gallery and Files content:// URIs directly to their real filesystem paths
 * in <1ms without copying gigabytes of data to app cache.
 */
object UriUtils {

    fun getRealPathFromUri(context: Context, uri: Uri): String? {
        try {
            // 1. Direct file:// scheme
            if (ContentResolver.SCHEME_FILE.equals(uri.scheme, ignoreCase = true)) {
                val path = uri.path
                if (path != null && File(path).exists()) return path
            }

            // 2. DocumentsContract DocumentUri (Android 4.4+)
            if (DocumentsContract.isDocumentUri(context, uri)) {
                val authority = uri.authority

                // ExternalStorageProvider (Files app, SD card, Internal Storage)
                if ("com.android.externalstorage.documents" == authority) {
                    val docId = DocumentsContract.getDocumentId(uri)
                    val split = docId.split(":")
                    if (split.isNotEmpty()) {
                        val type = split[0]
                        val relativePath = if (split.size > 1) split[1] else ""
                        if ("primary".equals(type, ignoreCase = true)) {
                            val path = "${Environment.getExternalStorageDirectory().absolutePath}/$relativePath"
                            if (File(path).exists()) return path
                        } else {
                            // Secondary SD card
                            val path = "/storage/$type/$relativePath"
                            if (File(path).exists()) return path
                        }
                    }
                }
                // MediaDocumentsProvider (Gallery, Photos via Document picker)
                else if ("com.android.providers.media.documents" == authority) {
                    val docId = DocumentsContract.getDocumentId(uri)
                    val split = docId.split(":")
                    if (split.size > 1) {
                        val type = split[0]
                        val id = split[1]
                        val contentUri = when (type.lowercase()) {
                            "image" -> MediaStore.Images.Media.EXTERNAL_CONTENT_URI
                            "video" -> MediaStore.Video.Media.EXTERNAL_CONTENT_URI
                            "audio" -> MediaStore.Audio.Media.EXTERNAL_CONTENT_URI
                            else -> MediaStore.Files.getContentUri("external")
                        }
                        val path = getDataColumn(context, contentUri, "_id=?", arrayOf(id))
                        if (!path.isNullOrEmpty() && File(path).exists()) return path
                    }
                }
                // DownloadsDocumentsProvider
                else if ("com.android.providers.downloads.documents" == authority) {
                    val id = DocumentsContract.getDocumentId(uri)
                    if (!id.isNullOrEmpty()) {
                        if (id.startsWith("raw:")) {
                            val path = id.substring(4)
                            if (File(path).exists()) return path
                        }
                        try {
                            val contentUri = ContentUris.withAppendedId(
                                Uri.parse("content://downloads/public_downloads"),
                                id.toLong()
                            )
                            val path = getDataColumn(context, contentUri, null, null)
                            if (!path.isNullOrEmpty() && File(path).exists()) return path
                        } catch (ignored: Exception) {}

                        // Try standard downloads directory
                        val path = "${Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS).absolutePath}/$id"
                        if (File(path).exists()) return path
                    }
                }
            }

            // 3. MediaStore & General Content URIs (Standard Share Sheet from Gallery / Photos / Files)
            if (ContentResolver.SCHEME_CONTENT.equals(uri.scheme, ignoreCase = true)) {
                // A. Direct DATA column query
                val path = getDataColumn(context, uri, null, null)
                val normDirect = normalizeToStoragePath(path)
                if (normDirect != null) return normDirect

                // B. Fallback: Check if file descriptor maps to a real filesystem path via Linux procfs
                try {
                    context.contentResolver.openFileDescriptor(uri, "r")?.use { pfd ->
                        val fd = pfd.fd
                        val procFile = File("/proc/self/fd/$fd")
                        val target = procFile.canonicalPath
                        if (!target.isNullOrEmpty() && !target.startsWith("/proc") && !target.startsWith("/pipe")) {
                            val normProc = normalizeToStoragePath(target)
                            if (normProc != null) return normProc
                        }
                    }
                } catch (ignored: Exception) {}

                // C. Fallback: Query by DISPLAY_NAME & SIZE in MediaStore (for PhotoPicker / Google Photos URIs)
                try {
                    var displayName: String? = null
                    var size: Long = -1L
                    val proj = arrayOf(android.provider.OpenableColumns.DISPLAY_NAME, android.provider.OpenableColumns.SIZE)
                    context.contentResolver.query(uri, proj, null, null, null)?.use { cursor ->
                        if (cursor.moveToFirst()) {
                            val nameIdx = cursor.getColumnIndex(android.provider.OpenableColumns.DISPLAY_NAME)
                            val sizeIdx = cursor.getColumnIndex(android.provider.OpenableColumns.SIZE)
                            if (nameIdx != -1) displayName = cursor.getString(nameIdx)
                            if (sizeIdx != -1) size = cursor.getLong(sizeIdx)
                        }
                    }

                    if (!displayName.isNullOrEmpty()) {
                        val selection = if (size > 0) {
                            "${MediaStore.MediaColumns.DISPLAY_NAME}=? AND ${MediaStore.MediaColumns.SIZE}=?"
                        } else {
                            "${MediaStore.MediaColumns.DISPLAY_NAME}=?"
                        }
                        val selectionArgs = if (size > 0) {
                            arrayOf(displayName!!, size.toString())
                        } else {
                            arrayOf(displayName!!)
                        }

                        val videoPath = getDataColumn(context, MediaStore.Video.Media.EXTERNAL_CONTENT_URI, selection, selectionArgs)
                        val normVideo = normalizeToStoragePath(videoPath)
                        if (normVideo != null) return normVideo

                        val imagePath = getDataColumn(context, MediaStore.Images.Media.EXTERNAL_CONTENT_URI, selection, selectionArgs)
                        val normImage = normalizeToStoragePath(imagePath)
                        if (normImage != null) return normImage

                        val filePath = getDataColumn(context, MediaStore.Files.getContentUri("external"), selection, selectionArgs)
                        val normFile = normalizeToStoragePath(filePath)
                        if (normFile != null) return normFile
                    }
                } catch (ignored: Exception) {}
            }
        } catch (e: Exception) {
            android.util.Log.e("ClipLAN_UriUtils", "Failed to resolve real path from URI: $uri", e)
        }

        return null
    }

    private fun normalizeToStoragePath(path: String?): String? {
        if (path.isNullOrEmpty()) return null
        var p = path
        if (p.startsWith("/data/media/0/")) {
            p = "/storage/emulated/0/" + p.substring("/data/media/0/".length)
        } else if (p.startsWith("/data/media/")) {
            val parts = p.split("/")
            if (parts.size >= 4) {
                val userId = parts[3]
                p = "/storage/emulated/$userId/" + p.substring("/data/media/$userId/".length)
            }
        } else if (p.startsWith("/mnt/user/0/primary/")) {
            p = "/storage/emulated/0/" + p.substring("/mnt/user/0/primary/".length)
        } else if (p.startsWith("/mnt/runtime/default/emulated/0/")) {
            p = "/storage/emulated/0/" + p.substring("/mnt/runtime/default/emulated/0/".length)
        } else if (p.startsWith("/mnt/runtime/read/emulated/0/")) {
            p = "/storage/emulated/0/" + p.substring("/mnt/runtime/read/emulated/0/".length)
        } else if (p.startsWith("/mnt/runtime/write/emulated/0/")) {
            p = "/storage/emulated/0/" + p.substring("/mnt/runtime/write/emulated/0/".length)
        } else if (p.startsWith("/storage/emulated/legacy/")) {
            p = "/storage/emulated/0/" + p.substring("/storage/emulated/legacy/".length)
        }
        return if (File(p).exists()) p else null
    }

    private fun getDataColumn(
        context: Context,
        uri: Uri,
        selection: String?,
        selectionArgs: Array<String>?
    ): String? {
        val column = MediaStore.MediaColumns.DATA
        val projection = arrayOf(column)
        try {
            context.contentResolver.query(uri, projection, selection, selectionArgs, null)?.use { cursor ->
                if (cursor.moveToFirst()) {
                    val columnIndex = cursor.getColumnIndex(column)
                    if (columnIndex != -1) {
                        return cursor.getString(columnIndex)
                    }
                }
            }
        } catch (ignored: Exception) {}
        return null
    }
}

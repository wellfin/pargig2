package com.pargig.app

import android.content.ContentValues
import android.content.Context
import android.media.MediaScannerConnection
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import java.io.File
import java.io.FileOutputStream

/**
 * Writes a file straight into the device's public Downloads folder.
 *
 * Exists because there is no way to do this from Dart. `path_provider`
 * has no Android Downloads directory, and the share sheet — which is
 * what the invoice used before — makes the user pick a destination for
 * something they already asked to download.
 *
 * Two routes, because Android changed how this works at API 29:
 *   API 29+  MediaStore. The system owns the file, so no storage
 *            permission is needed at all.
 *   API 28-  A direct write to the public directory, which does need
 *            WRITE_EXTERNAL_STORAGE — declared in the manifest with
 *            maxSdkVersion="28" so newer devices are never asked for it.
 */
object DownloadSaver {

    /**
     * @return where the file landed, for the confirmation message, or
     *         null if it could not be written. Never throws: the caller
     *         falls back to the share sheet, and a crash here would lose
     *         the invoice entirely.
     */
    fun save(
        context: Context,
        bytes: ByteArray,
        fileName: String,
        mimeType: String,
    ): String? = try {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            saveViaMediaStore(context, bytes, fileName, mimeType)
        } else {
            saveLegacy(context, bytes, fileName, mimeType)
        }
    } catch (e: Exception) {
        null
    }

    private fun saveViaMediaStore(
        context: Context,
        bytes: ByteArray,
        fileName: String,
        mimeType: String,
    ): String? {
        val resolver = context.contentResolver
        val pending = ContentValues().apply {
            put(MediaStore.Downloads.DISPLAY_NAME, fileName)
            put(MediaStore.Downloads.MIME_TYPE, mimeType)
            // Hides the row until the bytes are all written, so nothing
            // can open a half-written PDF.
            put(MediaStore.Downloads.IS_PENDING, 1)
        }

        val uri = resolver.insert(
            MediaStore.Downloads.EXTERNAL_CONTENT_URI,
            pending,
        ) ?: return null

        resolver.openOutputStream(uri)?.use { it.write(bytes) } ?: run {
            // Nothing was written, so take the placeholder row back out
            // rather than leaving an empty file in Downloads.
            resolver.delete(uri, null, null)
            return null
        }

        resolver.update(
            uri,
            ContentValues().apply { put(MediaStore.Downloads.IS_PENDING, 0) },
            null,
            null,
        )
        return "Downloads/$fileName"
    }

    private fun saveLegacy(
        context: Context,
        bytes: ByteArray,
        fileName: String,
        mimeType: String,
    ): String? {
        val dir = Environment.getExternalStoragePublicDirectory(
            Environment.DIRECTORY_DOWNLOADS,
        )
        if (!dir.exists() && !dir.mkdirs()) return null

        val file = File(dir, fileName)
        FileOutputStream(file).use { it.write(bytes) }

        // Without this the file exists but the Downloads app and any
        // file manager keep showing the folder as it was.
        MediaScannerConnection.scanFile(
            context,
            arrayOf(file.absolutePath),
            arrayOf(mimeType),
            null,
        )
        return "Downloads/$fileName"
    }
}

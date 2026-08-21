package com.yourcompany.employee_app

import android.app.Activity
import android.content.ContentResolver
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.IOException
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

internal fun interface AttachmentOutputWriter {
    fun write(uri: Uri, bytes: ByteArray)
}

internal fun interface AttachmentDocumentCleaner {
    fun delete(uri: Uri)
}

internal class ContentResolverAttachmentOutputWriter(
    private val contentResolver: ContentResolver,
) : AttachmentOutputWriter {
    override fun write(uri: Uri, bytes: ByteArray) {
        val output = contentResolver.openOutputStream(uri, "w")
            ?: throw IOException("Unable to open attachment output stream")
        output.use { stream ->
            stream.write(bytes)
            stream.flush()
        }
    }
}

internal class ContentResolverAttachmentDocumentCleaner(
    private val contentResolver: ContentResolver,
) : AttachmentDocumentCleaner {
    override fun delete(uri: Uri) {
        contentResolver.delete(uri, null, null)
    }
}

internal class AttachmentDocumentSaver(
    private val activity: FlutterActivity,
    messenger: BinaryMessenger,
    private val executor: ExecutorService = Executors.newSingleThreadExecutor { runnable ->
        Thread(runnable, "attachment-document-writer")
    },
    private val mainHandler: Handler = Handler(Looper.getMainLooper()),
    private val outputWriter: AttachmentOutputWriter =
        ContentResolverAttachmentOutputWriter(activity.contentResolver),
    private val documentCleaner: AttachmentDocumentCleaner =
        ContentResolverAttachmentDocumentCleaner(activity.contentResolver),
) {
    companion object {
        const val CHANNEL_NAME =
            "com.yourcompany.employee_app/attachment_document_saver"
        private const val METHOD_SAVE_ATTACHMENT = "saveAttachment"
        private const val CREATE_DOCUMENT_REQUEST_CODE = 0xA771
        private const val MAX_BYTES = 10 * 1024 * 1024
        private val ALLOWED_MIME_TYPES = setOf(
            "application/pdf",
            "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
            "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
            "image/jpeg",
            "image/png",
        )
    }

    private data class PendingSave(
        val bytes: ByteArray,
        val result: MethodChannel.Result,
        var writing: Boolean = false,
        var uri: Uri? = null,
    )

    private val channel = MethodChannel(messenger, CHANNEL_NAME)
    @Volatile
    private var disposed = false
    private var pendingSave: PendingSave? = null
    private val writeLifecycle = AttachmentWriteLifecycle(executor) { callback ->
        mainHandler.post { callback() }
    }

    init {
        channel.setMethodCallHandler(::handleMethodCall)
    }

    fun dispose() {
        if (disposed) {
            return
        }
        channel.setMethodCallHandler(null)
        val pending = pendingSave
        pendingSave = null
        disposed = true
        mainHandler.removeCallbacksAndMessages(null)
        if (pending != null && !pending.writing) {
            pending.result.error(
                "attachment_save_cancelled",
                "附件保存已取消。",
                null,
            )
        }
        writeLifecycle.dispose()
    }

    private fun handleMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != METHOD_SAVE_ATTACHMENT) {
            result.notImplemented()
            return
        }
        if (pendingSave != null) {
            result.error(
                "attachment_save_in_progress",
                "已有附件正在保存。",
                null,
            )
            return
        }

        val bytes = call.argument<ByteArray>("bytes")
        val filename = call.argument<String>("filename")
        val mimeType = call.argument<String>("mimeType")
        if (!validArguments(bytes, filename, mimeType)) {
            result.error(
                "attachment_invalid_arguments",
                "附件保存参数无效。",
                null,
            )
            return
        }

        pendingSave = PendingSave(bytes!!, result)
        val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = mimeType
            putExtra(Intent.EXTRA_TITLE, filename)
        }
        try {
            activity.startActivityForResult(intent, CREATE_DOCUMENT_REQUEST_CODE)
        } catch (_: RuntimeException) {
            finishPending(pendingSave!!) { pendingResult ->
                pendingResult.error(
                    "attachment_save_unavailable",
                    "当前设备无法打开附件保存位置。",
                    null,
                )
            }
        }
    }

    fun handleActivityResult(
        requestCode: Int,
        resultCode: Int,
        data: Intent?,
    ): Boolean {
        if (requestCode != CREATE_DOCUMENT_REQUEST_CODE) {
            return false
        }
        completeSave(resultCode, data?.data)
        return true
    }

    private fun validArguments(
        bytes: ByteArray?,
        filename: String?,
        mimeType: String?,
    ): Boolean =
        bytes != null &&
            bytes.isNotEmpty() &&
            bytes.size <= MAX_BYTES &&
            filename != null &&
            filename.isNotBlank() &&
            filename.codePointCount(0, filename.length) <= 255 &&
            !filename.contains('/') &&
            !filename.contains('\\') &&
            !filename.contains('\r') &&
            !filename.contains('\n') &&
            mimeType in ALLOWED_MIME_TYPES

    private fun completeSave(resultCode: Int, uri: Uri?) {
        val pending = pendingSave ?: return
        if (pending.writing) {
            return
        }
        if (resultCode != Activity.RESULT_OK) {
            finishPending(pending) { result -> result.success(null) }
            return
        }
        if (uri == null) {
            finishPending(pending, ::completeWithSaveFailure)
            return
        }

        pending.writing = true
        pending.uri = uri
        writeLifecycle.execute(
            write = { outputWriter.write(uri, pending.bytes) },
            cleanup = { documentCleaner.delete(uri) },
            complete = { succeeded ->
                finishPending(pending) { result ->
                    if (succeeded) {
                        result.success(uri.toString())
                    } else {
                        completeWithSaveFailure(result)
                    }
                }
            },
        )
    }

    private fun finishPending(
        pending: PendingSave,
        completion: (MethodChannel.Result) -> Unit,
    ) {
        if (disposed || pendingSave !== pending) {
            return
        }
        pendingSave = null
        completion(pending.result)
    }

    private fun completeWithSaveFailure(result: MethodChannel.Result) {
        result.error(
            "attachment_save_failed",
            "附件保存失败。",
            null,
        )
    }
}

package com.yourcompany.employee_app

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private var attachmentDocumentSaver: AttachmentDocumentSaver? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        attachmentDocumentSaver = AttachmentDocumentSaver(
            this,
            flutterEngine.dartExecutor.binaryMessenger,
        )
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        attachmentDocumentSaver?.dispose()
        attachmentDocumentSaver = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun onActivityResult(
        requestCode: Int,
        resultCode: Int,
        data: Intent?,
    ) {
        if (
            attachmentDocumentSaver?.handleActivityResult(
                requestCode,
                resultCode,
                data,
            ) == true
        ) {
            return
        }
        super.onActivityResult(requestCode, resultCode, data)
    }
}

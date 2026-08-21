package com.yourcompany.employee_app

import java.util.concurrent.ExecutorService
import java.util.concurrent.RejectedExecutionException

internal class AttachmentWriteLifecycle(
    private val executor: ExecutorService,
    private val postToMain: ((() -> Unit) -> Unit),
) {
    @Volatile
    private var disposed = false

    fun execute(
        write: () -> Unit,
        cleanup: () -> Unit,
        complete: (Boolean) -> Unit,
    ) {
        try {
            executor.execute {
                val succeeded = try {
                    write()
                    true
                } catch (_: Exception) {
                    cleanupSafely(cleanup)
                    false
                }
                if (disposed) {
                    return@execute
                }
                postToMain {
                    if (!disposed) {
                        complete(succeeded)
                    }
                }
            }
        } catch (_: RejectedExecutionException) {
            cleanupSafely(cleanup)
            if (!disposed) {
                postToMain {
                    if (!disposed) {
                        complete(false)
                    }
                }
            }
        }
    }

    fun dispose() {
        if (disposed) {
            return
        }
        disposed = true
        executor.shutdown()
    }

    private fun cleanupSafely(cleanup: () -> Unit) {
        try {
            cleanup()
        } catch (_: Exception) {
            // The write failure remains authoritative; cleanup is best effort.
        }
    }
}

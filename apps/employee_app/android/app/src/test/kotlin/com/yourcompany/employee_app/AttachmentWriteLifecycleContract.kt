package com.yourcompany.employee_app

import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger

object AttachmentWriteLifecycleContract {
    @JvmStatic
    fun main(arguments: Array<String>) {
        check(arguments.isEmpty())
        acceptedWriteFinishesWithoutCallbackAfterDispose()
        failedWriteDeletesDocumentWithoutCallbackAfterDispose()
        println("AttachmentWriteLifecycleContract: PASS")
    }

    private fun acceptedWriteFinishesWithoutCallbackAfterDispose() {
        val executor = Executors.newSingleThreadExecutor()
        val lifecycle = AttachmentWriteLifecycle(executor) { callback -> callback() }
        val started = CountDownLatch(1)
        val release = CountDownLatch(1)
        val finished = CountDownLatch(1)
        val interrupted = AtomicBoolean(false)
        val completions = AtomicInteger(0)
        val cleanups = AtomicInteger(0)

        lifecycle.execute(
            write = {
                started.countDown()
                try {
                    check(release.await(5, TimeUnit.SECONDS))
                } catch (_: InterruptedException) {
                    interrupted.set(true)
                } finally {
                    finished.countDown()
                }
            },
            cleanup = { cleanups.incrementAndGet() },
            complete = { completions.incrementAndGet() },
        )
        check(started.await(5, TimeUnit.SECONDS))

        lifecycle.dispose()
        release.countDown()

        check(finished.await(5, TimeUnit.SECONDS))
        check(executor.awaitTermination(5, TimeUnit.SECONDS))
        check(!interrupted.get())
        check(completions.get() == 0)
        check(cleanups.get() == 0)
    }

    private fun failedWriteDeletesDocumentWithoutCallbackAfterDispose() {
        val executor = Executors.newSingleThreadExecutor()
        val lifecycle = AttachmentWriteLifecycle(executor) { callback -> callback() }
        val started = CountDownLatch(1)
        val release = CountDownLatch(1)
        val cleaned = CountDownLatch(1)
        val completions = AtomicInteger(0)

        lifecycle.execute(
            write = {
                started.countDown()
                check(release.await(5, TimeUnit.SECONDS))
                throw IllegalStateException("fake provider failure")
            },
            cleanup = { cleaned.countDown() },
            complete = { completions.incrementAndGet() },
        )
        check(started.await(5, TimeUnit.SECONDS))

        lifecycle.dispose()
        release.countDown()

        check(cleaned.await(5, TimeUnit.SECONDS))
        check(executor.awaitTermination(5, TimeUnit.SECONDS))
        check(completions.get() == 0)
    }
}

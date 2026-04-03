package com.caddieai.android.data.telemetry

import android.content.Context
import androidx.hilt.work.HiltWorker
import androidx.work.CoroutineWorker
import androidx.work.WorkerParameters
import dagger.assisted.Assisted
import dagger.assisted.AssistedInject

@HiltWorker
class TelemetryFlushWorker @AssistedInject constructor(
    @Assisted context: Context,
    @Assisted params: WorkerParameters,
    private val telemetryService: TelemetryService,
) : CoroutineWorker(context, params) {

    override suspend fun doWork(): Result {
        telemetryService.flush()
        return Result.success()
    }
}

package com.caddieai.android.data.location

import android.annotation.SuppressLint
import android.content.Context
import android.location.Location
import com.caddieai.android.data.course.CourseCacheService
import com.caddieai.android.data.model.GeoPoint
import com.google.android.gms.location.FusedLocationProviderClient
import com.google.android.gms.location.LocationServices
import com.google.android.gms.location.Priority
import com.google.android.gms.tasks.CancellationTokenSource
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.suspendCancellableCoroutine
import javax.inject.Inject
import javax.inject.Singleton
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

private const val NEARBY_COURSE_RADIUS_YARDS = 2200.0 // ~2km

@Singleton
class LocationService @Inject constructor(
    @ApplicationContext private val context: Context,
    private val cacheService: CourseCacheService,
) {
    private val fusedClient: FusedLocationProviderClient =
        LocationServices.getFusedLocationProviderClient(context)

    private val _currentLocation = MutableStateFlow<GeoPoint?>(null)
    val currentLocation: StateFlow<GeoPoint?> = _currentLocation.asStateFlow()

    @SuppressLint("MissingPermission")
    suspend fun getCurrentLocation(): Result<GeoPoint> {
        return try {
            val cts = CancellationTokenSource()
            val location = suspendCancellableCoroutine<Location> { cont ->
                fusedClient.getCurrentLocation(Priority.PRIORITY_HIGH_ACCURACY, cts.token)
                    .addOnSuccessListener { loc ->
                        if (loc != null) cont.resume(loc)
                        else cont.resumeWithException(Exception("Location unavailable"))
                    }
                    .addOnFailureListener { e -> cont.resumeWithException(e) }
                cont.invokeOnCancellation { cts.cancel() }
            }
            val point = GeoPoint(location.latitude, location.longitude)
            _currentLocation.value = point
            Result.success(point)
        } catch (e: Exception) {
            Result.failure(e)
        }
    }

    fun findNearbyCourses(location: GeoPoint) =
        cacheService.coursesNear(location, NEARBY_COURSE_RADIUS_YARDS)
}

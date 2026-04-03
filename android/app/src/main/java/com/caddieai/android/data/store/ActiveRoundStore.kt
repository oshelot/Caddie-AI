package com.caddieai.android.data.store

import com.caddieai.android.data.model.NormalizedCourse
import com.caddieai.android.data.model.ShotContext
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class ActiveRoundStore @Inject constructor() {
    private val _activeCourse = MutableStateFlow<NormalizedCourse?>(null)
    val activeCourse: StateFlow<NormalizedCourse?> = _activeCourse.asStateFlow()

    private val _activeHoleNumber = MutableStateFlow<Int?>(null)
    val activeHoleNumber: StateFlow<Int?> = _activeHoleNumber.asStateFlow()

    /** Pending pre-filled context from Course Map "Ask Caddie" → consumed by Caddie tab. */
    private val _pendingShotContext = MutableStateFlow<ShotContext?>(null)
    val pendingShotContext: StateFlow<ShotContext?> = _pendingShotContext.asStateFlow()

    fun setActiveCourse(course: NormalizedCourse?) { _activeCourse.value = course }
    fun setActiveHole(number: Int?) { _activeHoleNumber.value = number }
    fun setPendingShotContext(ctx: ShotContext?) { _pendingShotContext.value = ctx }
    fun consumePendingShotContext(): ShotContext? {
        val ctx = _pendingShotContext.value
        _pendingShotContext.value = null
        return ctx
    }
}

package com.caddieai.android.ui.theme

import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.ui.unit.dp

object CaddieShape {
    /** Large cards, bottom sheets (iOS: 16pt corner) */
    val large = RoundedCornerShape(16.dp)
    /** Medium cards, dialogs (iOS: 12pt corner) */
    val medium = RoundedCornerShape(12.dp)
    /** Form fields, text inputs (iOS: 10pt corner) */
    val form = RoundedCornerShape(10.dp)
    /** Small callouts, chips, tags (iOS: 8pt corner) */
    val small = RoundedCornerShape(8.dp)
    /** Pill buttons, badges (iOS: Capsule) */
    val capsule = RoundedCornerShape(50)
    /** Avatars, icon backgrounds (iOS: Circle) */
    val circle = CircleShape
}
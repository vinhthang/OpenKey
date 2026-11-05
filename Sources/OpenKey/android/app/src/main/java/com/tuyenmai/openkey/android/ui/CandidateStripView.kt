package com.tuyenmai.openkey.android.ui

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.tuyenmai.openkey.core.OneHandedMode
import com.tuyenmai.openkey.core.ThemePalette
import com.tuyenmai.openkey.core.WordCandidate

/**
 * Crisp Vector Icons for Samsung One UI Candidate Strip Toolbar (REQ-020, ADR-021).
 */
@Composable
fun OneHandedModeIcon(
    oneHandedMode: OneHandedMode,
    tint: Color,
    modifier: Modifier = Modifier
) {
    Canvas(modifier = modifier.size(20.dp)) {
        val w = size.width
        val h = size.height
        val strokeWidth = 1.6.dp.toPx()

        // Smartphone outline
        val phoneRect = Path().apply {
            addRoundRect(
                androidx.compose.ui.geometry.RoundRect(
                    left = w * 0.22f,
                    top = h * 0.12f,
                    right = w * 0.78f,
                    bottom = h * 0.88f,
                    radiusX = 3.dp.toPx(),
                    radiusY = 3.dp.toPx()
                )
            )
        }
        drawPath(
            phoneRect,
            color = tint,
            style = Stroke(width = strokeWidth)
        )

        // Bottom home bar
        drawLine(
            color = tint,
            start = Offset(w * 0.40f, h * 0.78f),
            end = Offset(w * 0.60f, h * 0.78f),
            strokeWidth = strokeWidth,
            cap = StrokeCap.Round
        )

        // One-handed arrow or dock line inside screen
        when (oneHandedMode) {
            OneHandedMode.LEFT -> {
                val arrow = Path().apply {
                    moveTo(w * 0.58f, h * 0.38f)
                    lineTo(w * 0.42f, h * 0.50f)
                    lineTo(w * 0.58f, h * 0.62f)
                }
                drawPath(arrow, color = tint, style = Stroke(width = strokeWidth, cap = StrokeCap.Round, join = StrokeJoin.Round))
            }
            OneHandedMode.RIGHT -> {
                val arrow = Path().apply {
                    moveTo(w * 0.42f, h * 0.38f)
                    lineTo(w * 0.58f, h * 0.50f)
                    lineTo(w * 0.42f, h * 0.62f)
                }
                drawPath(arrow, color = tint, style = Stroke(width = strokeWidth, cap = StrokeCap.Round, join = StrokeJoin.Round))
            }
            OneHandedMode.OFF -> {
                drawLine(
                    color = tint.copy(alpha = 0.5f),
                    start = Offset(w * 0.32f, h * 0.48f),
                    end = Offset(w * 0.68f, h * 0.48f),
                    strokeWidth = strokeWidth * 0.8f,
                    cap = StrokeCap.Round
                )
            }
        }
    }
}

@Composable
fun SettingsGearIcon(
    tint: Color,
    modifier: Modifier = Modifier
) {
    Canvas(modifier = modifier.size(20.dp)) {
        val w = size.width
        val h = size.height
        val center = Offset(w / 2f, h / 2f)
        val outerRadius = w * 0.42f
        val innerRadius = w * 0.30f
        val holeRadius = w * 0.15f
        val strokeWidth = 1.6.dp.toPx()

        drawCircle(
            color = tint,
            radius = holeRadius,
            center = center,
            style = Stroke(width = strokeWidth)
        )

        drawCircle(
            color = tint,
            radius = innerRadius,
            center = center,
            style = Stroke(width = strokeWidth)
        )

        for (i in 0 until 6) {
            val angleRad = (i * 60.0 * Math.PI / 180.0).toFloat()
            val cosA = kotlin.math.cos(angleRad)
            val sinA = kotlin.math.sin(angleRad)
            val start = Offset(center.x + innerRadius * cosA, center.y + innerRadius * sinA)
            val end = Offset(center.x + outerRadius * cosA, center.y + outerRadius * sinA)
            drawLine(
                color = tint,
                start = start,
                end = end,
                strokeWidth = strokeWidth * 1.5f,
                cap = StrokeCap.Round
            )
        }
    }
}

/**
 * Samsung Galaxy A37 One UI Top Toolbar & Candidate Strip (REQ-004, REQ-020, ADR-004, ADR-021).
 * When candidates are present: displays 3 equal-width suggestions with center primary highlight.
 * When idle: displays a sleek One UI toolbar (mode indicator on left, vector icons on right).
 */
@Composable
fun CandidateStripView(
    candidates: List<WordCandidate>,
    heightDp: Float,
    palette: ThemePalette,
    language: Int,
    inputType: Int,
    oneHandedMode: OneHandedMode,
    onCandidateSelected: (WordCandidate) -> Unit,
    onLanguageToggled: () -> Unit,
    onInputTypeToggled: () -> Unit,
    onOneHandedCycle: () -> Unit,
    onOpenSettings: () -> Unit,
    modifier: Modifier = Modifier
) {
    val theme = palette
    val stripHeight = heightDp.dp

    Box(
        modifier = modifier
            .fillMaxWidth()
            .height(stripHeight)
            .background(Color(theme.backgroundColor)),
        contentAlignment = Alignment.Center
    ) {
        if (candidates.isNotEmpty()) {
            val orderedSlots = listOf(
                candidates.getOrNull(1),
                candidates.getOrNull(0),
                candidates.getOrNull(2)
            )

            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .fillMaxHeight(),
                verticalAlignment = Alignment.CenterVertically
            ) {
                orderedSlots.forEachIndexed { index, candidate ->
                    if (index > 0) {
                        Box(
                            modifier = Modifier
                                .width(1.dp)
                                .height(20.dp)
                                .background(Color(theme.borderColor).copy(alpha = 0.5f))
                        )
                    }

                    val isCenter = (index == 1)

                    Box(
                        modifier = Modifier
                            .weight(1f)
                            .fillMaxHeight()
                            .padding(horizontal = 4.dp, vertical = 4.dp)
                            .then(
                                if (isCenter && candidate != null) {
                                    Modifier.background(
                                        Color(theme.accentColor).copy(alpha = 0.12f),
                                        RoundedCornerShape(16.dp)
                                    )
                                } else {
                                    Modifier
                                }
                            )
                            .clickable(
                                enabled = candidate != null,
                                interactionSource = remember { MutableInteractionSource() },
                                indication = null
                            ) {
                                candidate?.let { onCandidateSelected(it) }
                            },
                        contentAlignment = Alignment.Center
                    ) {
                        if (candidate != null) {
                            Text(
                                text = candidate.text,
                                color = Color(theme.primaryTextColor),
                                fontSize = if (isCenter) 17.sp else 16.sp,
                                fontWeight = if (isCenter) FontWeight.SemiBold else FontWeight.Normal,
                                maxLines = 1,
                                overflow = TextOverflow.Ellipsis,
                                textAlign = TextAlign.Center
                            )
                        }
                    }
                }
            }
        } else {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .fillMaxHeight()
                    .padding(horizontal = 14.dp),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                // Left side: subtle mode indicator
                val modeText = if (language == 1) {
                    "Tiếng Việt • ${if (inputType == 0) "Telex" else "VNI"}"
                } else {
                    "English (US)"
                }

                Text(
                    text = modeText,
                    fontSize = 13.sp,
                    fontWeight = FontWeight.Medium,
                    color = Color(theme.secondaryTextColor),
                    modifier = Modifier.clickable(
                        interactionSource = remember { MutableInteractionSource() },
                        indication = null
                    ) {
                        if (language == 1) {
                            onInputTypeToggled()
                        } else {
                            onLanguageToggled()
                        }
                    }
                )

                // Right side: two borderless 36.dp x 36.dp Canvas vector icon buttons
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(4.dp)
                ) {
                    Box(
                        modifier = Modifier
                            .size(36.dp)
                            .clickable(
                                interactionSource = remember { MutableInteractionSource() },
                                indication = null
                            ) {
                                onOneHandedCycle()
                            },
                        contentAlignment = Alignment.Center
                    ) {
                        OneHandedModeIcon(
                            oneHandedMode = oneHandedMode,
                            tint = Color(theme.secondaryTextColor)
                        )
                    }

                    Box(
                        modifier = Modifier
                            .size(36.dp)
                            .clickable(
                                interactionSource = remember { MutableInteractionSource() },
                                indication = null
                            ) {
                                onOpenSettings()
                            },
                        contentAlignment = Alignment.Center
                    ) {
                        SettingsGearIcon(
                            tint = Color(theme.secondaryTextColor)
                        )
                    }
                }
            }
        }
    }
}

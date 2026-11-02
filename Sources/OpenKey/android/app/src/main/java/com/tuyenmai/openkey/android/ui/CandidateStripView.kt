package com.tuyenmai.openkey.android.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.tuyenmai.openkey.core.OneHandedMode
import com.tuyenmai.openkey.core.ThemePalette
import com.tuyenmai.openkey.core.WordCandidate

/**
 * Samsung Galaxy A37 One UI Top Toolbar & Candidate Strip (REQ-004, REQ-007, ADR-004, ADR-007).
 * When candidates are present: displays 3 equal-width suggestions with 1dp dividers.
 * When idle: displays a clean One UI toolbar (VI/EN pill, Telex/VNI chip, One-Handed toggle, Settings gear).
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
    val stripHeight = heightDp.dp

    Box(
        modifier = modifier
            .fillMaxWidth()
            .height(stripHeight)
            .background(Color(palette.backgroundColor)),
        contentAlignment = Alignment.Center
    ) {
        if (candidates.isNotEmpty()) {
            val visibleCandidates = candidates.take(3)
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .fillMaxHeight(),
                verticalAlignment = Alignment.CenterVertically
            ) {
                visibleCandidates.forEachIndexed { index, candidate ->
                    if (index > 0) {
                        Box(
                            modifier = Modifier
                                .width(1.dp)
                                .height(22.dp)
                                .background(Color(palette.borderColor))
                        )
                    }
                    Box(
                        modifier = Modifier
                            .weight(1f)
                            .fillMaxHeight()
                            .clickable(
                                interactionSource = remember { MutableInteractionSource() },
                                indication = null
                            ) {
                                onCandidateSelected(candidate)
                            },
                        contentAlignment = Alignment.Center
                    ) {
                        Text(
                            text = candidate.text,
                            color = Color(palette.primaryTextColor),
                            fontSize = 15.sp,
                            fontWeight = FontWeight.Medium,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis,
                            textAlign = TextAlign.Center
                        )
                    }
                }
            }
        } else {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .fillMaxHeight()
                    .padding(horizontal = 12.dp),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                // Language pill: VI / EN
                Box(
                    modifier = Modifier
                        .clickable { onLanguageToggled() }
                        .background(Color(palette.functionalKeycapColor), RoundedCornerShape(12.dp))
                        .padding(horizontal = 14.dp, vertical = 6.dp),
                    contentAlignment = Alignment.Center
                ) {
                    Text(
                        text = if (language == 1) "VI" else "EN",
                        color = Color(palette.primaryTextColor),
                        fontSize = 13.sp,
                        fontWeight = FontWeight.Bold
                    )
                }

                // Input type chip: Telex / VNI
                Box(
                    modifier = Modifier
                        .clickable { onInputTypeToggled() }
                        .background(Color(palette.functionalKeycapColor), RoundedCornerShape(12.dp))
                        .padding(horizontal = 14.dp, vertical = 6.dp),
                    contentAlignment = Alignment.Center
                ) {
                    Text(
                        text = if (inputType == 0) "Telex" else "VNI",
                        color = Color(palette.primaryTextColor),
                        fontSize = 13.sp,
                        fontWeight = FontWeight.SemiBold
                    )
                }

                // One-Handed mode cycle: Full / Left 82% / Right 82%
                val oneHandedLabel = when (oneHandedMode) {
                    OneHandedMode.OFF -> "Full"
                    OneHandedMode.LEFT -> "Left 82%"
                    OneHandedMode.RIGHT -> "Right 82%"
                }
                Box(
                    modifier = Modifier
                        .clickable { onOneHandedCycle() }
                        .background(Color(palette.functionalKeycapColor), RoundedCornerShape(12.dp))
                        .padding(horizontal = 12.dp, vertical = 6.dp),
                    contentAlignment = Alignment.Center
                ) {
                    Text(
                        text = oneHandedLabel,
                        color = Color(palette.primaryTextColor),
                        fontSize = 13.sp,
                        fontWeight = FontWeight.Medium
                    )
                }

                // Settings gear
                Box(
                    modifier = Modifier
                        .clickable { onOpenSettings() }
                        .background(Color(palette.functionalKeycapColor), RoundedCornerShape(12.dp))
                        .padding(horizontal = 12.dp, vertical = 6.dp),
                    contentAlignment = Alignment.Center
                ) {
                    Text(
                        text = "⚙",
                        color = Color(palette.primaryTextColor),
                        fontSize = 14.sp,
                        fontWeight = FontWeight.Bold
                    )
                }
            }
        }
    }
}

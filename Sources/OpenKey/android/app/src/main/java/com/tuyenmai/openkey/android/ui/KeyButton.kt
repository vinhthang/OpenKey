package com.tuyenmai.openkey.android.ui

import android.view.HapticFeedbackConstants
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.input.pointer.positionChange
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Popup
import androidx.compose.ui.window.PopupProperties
import com.tuyenmai.openkey.core.ComputedKeyboardMetrics
import com.tuyenmai.openkey.core.GestureAction
import com.tuyenmai.openkey.core.KeyAction
import com.tuyenmai.openkey.core.KeyModel
import com.tuyenmai.openkey.core.KeyboardGestureController
import com.tuyenmai.openkey.core.ThemePalette
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch

/**
 * Samsung Galaxy A37 One UI Individual Keycap (REQ-007, REQ-008, ADR-007, ADR-008).
 * Supports:
 * - 6dp rounded keycap surface with subtle 1dp border
 * - Centered primary label + top-right secondary symbol sub-label
 * - Haptic feedback (HapticFeedbackConstants.KEYBOARD_TAP)
 * - Key popup preview bubble
 * - Spacebar horizontal drag cursor-trackpad mode (< Tiếng Việt >)
 * - Backspace leftward swipe-delete and hold-repeat
 * - 220ms long-press Vietnamese vowel & symbol variants
 */
@Composable
fun KeyButton(
    key: KeyModel,
    metrics: ComputedKeyboardMetrics,
    palette: ThemePalette,
    hapticFeedbackEnabled: Boolean,
    keyPopupPreviewEnabled: Boolean,
    gestureController: KeyboardGestureController,
    onKeyPressed: (KeyAction) -> Unit,
    onMoveCursor: (Int) -> Unit,
    onDeleteWord: () -> Unit,
    modifier: Modifier = Modifier
) {
    val view = LocalView.current
    val density = LocalDensity.current
    val scope = rememberCoroutineScope()

    var isPressed by remember { mutableStateOf(false) }
    var showVariantsPopup by remember { mutableStateOf(false) }
    var variantOptions by remember { mutableStateOf<List<String>>(emptyList()) }
    var spacebarTrackpadLabel by remember { mutableStateOf<String?>(null) }

    val cornerRadius = metrics.keyCornerRadiusDp.dp
    val gapH = (metrics.keyHorizontalGapDp / 2).dp
    val gapV = (metrics.keyVerticalGapDp / 2).dp

    val keyBgColor = if (key.isFunctional) {
        Color(palette.functionalKeycapColor)
    } else {
        Color(palette.keycapColor)
    }

    val strokeWidthPx = with(density) { 1.dp.toPx() }
    val bevelHeightPx = with(density) { 1.dp.toPx() }
    val cornerRadiusPx = with(density) { cornerRadius.toPx() }
    val borderColor = Color(palette.borderColor)

    Box(
        modifier = modifier
            .fillMaxSize()
            .padding(horizontal = gapH, vertical = gapV)
            .drawBehind {
                val r = CornerRadius(cornerRadiusPx, cornerRadiusPx)
                if (!isPressed) {
                    drawRoundRect(
                        color = Color(0x33000000),
                        topLeft = Offset(0f, bevelHeightPx),
                        size = size,
                        cornerRadius = r
                    )
                }
                drawRoundRect(
                    color = keyBgColor,
                    topLeft = Offset.Zero,
                    size = size,
                    cornerRadius = r
                )
                drawRoundRect(
                    color = borderColor,
                    topLeft = Offset.Zero,
                    size = size,
                    cornerRadius = r,
                    style = Stroke(width = strokeWidthPx)
                )
            }
            .pointerInput(key) {
                awaitEachGesture {
                    val down = awaitFirstDown(requireUnconsumed = false)
                    isPressed = true

                    if (hapticFeedbackEnabled) {
                        view.performHapticFeedback(HapticFeedbackConstants.KEYBOARD_TAP)
                    }

                    var longPressJob: Job? = null
                    var repeatDeleteJob: Job? = null
                    var longPressHandled = false
                    var didRepeatDelete = false

                    when (key.action) {
                        is KeyAction.Space -> {
                            gestureController.onSpacebarDown()
                            spacebarTrackpadLabel = null
                        }
                        is KeyAction.Backspace -> {
                            gestureController.onBackspaceDown()
                            repeatDeleteJob = scope.launch {
                                delay(400L)
                                while (isActive) {
                                    didRepeatDelete = true
                                    onKeyPressed(KeyAction.Backspace)
                                    delay(50L)
                                }
                            }
                        }
                        else -> {
                            longPressJob = scope.launch {
                                delay(KeyboardGestureController.LONG_PRESS_TIMEOUT_MS)
                                val variants = gestureController.resolveLongPressVariants(key.primaryLabel)
                                if (variants.isNotEmpty()) {
                                    variantOptions = variants
                                    showVariantsPopup = true
                                    longPressHandled = true
                                } else {
                                    val secondary = key.secondaryLabel
                                    if (secondary != null) {
                                        onKeyPressed(KeyAction.CommitChar(secondary))
                                        longPressHandled = true
                                    }
                                }
                            }
                        }
                    }

                    var pointer = down
                    while (pointer.pressed) {
                        val event = awaitPointerEvent()
                        val change = event.changes.firstOrNull { it.id == pointer.id } ?: break

                        if (change.pressed != pointer.pressed) {
                            pointer = change
                            break
                        }

                        val dragDeltaX = change.positionChange().x
                        if (dragDeltaX != 0f) {
                            val deltaDp = with(density) { dragDeltaX.toDp().value }

                            when (key.action) {
                                is KeyAction.Space -> {
                                    val actions = gestureController.onSpacebarDrag(deltaDp)
                                    if (gestureController.isTrackpadActive) {
                                        spacebarTrackpadLabel = "<  ${key.primaryLabel}  >"
                                        for (act in actions) {
                                            if (act is GestureAction.CursorMove) {
                                                onMoveCursor(act.steps)
                                            }
                                        }
                                    }
                                }
                                is KeyAction.Backspace -> {
                                    val actions = gestureController.onBackspaceDrag(deltaDp)
                                    if (gestureController.isSwipeDeleteActive) {
                                        repeatDeleteJob?.cancel()
                                        for (act in actions) {
                                            if (act is GestureAction.DeletePreviousWord) {
                                                onDeleteWord()
                                            }
                                        }
                                    }
                                }
                                else -> {
                                    // if moved significantly, cancel long press
                                    if (kotlin.math.abs(dragDeltaX) > 10f) {
                                        longPressJob?.cancel()
                                    }
                                }
                            }
                        }
                        pointer = change
                    }

                    // Touch released or cancelled
                    isPressed = false
                    longPressJob?.cancel()
                    repeatDeleteJob?.cancel()

                    when (key.action) {
                        is KeyAction.Space -> {
                            val result = gestureController.onSpacebarUp()
                            spacebarTrackpadLabel = null
                            if (result is GestureAction.CommitSpace) {
                                onKeyPressed(KeyAction.Space)
                            }
                        }
                        is KeyAction.Backspace -> {
                            val result = gestureController.onBackspaceUp()
                            if (result is GestureAction.DeleteSingleChar && !didRepeatDelete) {
                                onKeyPressed(KeyAction.Backspace)
                            }
                        }
                        else -> {
                            if (!longPressHandled && !showVariantsPopup) {
                                onKeyPressed(key.action)
                            }
                        }
                    }
                }
            },
        contentAlignment = Alignment.Center
    ) {
        // Display label: Spacebar trackpad feedback or normal primary label
        val label = if (key.action is KeyAction.Space && spacebarTrackpadLabel != null) {
            spacebarTrackpadLabel!!
        } else {
            key.primaryLabel
        }

        val fontSize = when {
            key.action is KeyAction.Space -> 14.sp
            key.primaryLabel.length > 2 -> 13.sp
            else -> 19.sp
        }

        Text(
            text = label,
            color = Color(palette.primaryTextColor),
            fontSize = fontSize,
            fontWeight = if (key.isFunctional) FontWeight.Medium else FontWeight.Normal,
            textAlign = TextAlign.Center
        )

        // Top-right secondary symbol sub-label
        val secondary = key.secondaryLabel
        if (secondary != null && !key.isFunctional) {
            Text(
                text = secondary,
                color = Color(palette.secondaryTextColor),
                fontSize = 10.sp,
                fontWeight = FontWeight.Medium,
                modifier = Modifier
                    .align(Alignment.TopEnd)
                    .padding(end = 5.dp, top = 2.dp)
            )
        }

        // Floating Key Popup Preview Bubble (One UI style)
        if (isPressed && keyPopupPreviewEnabled && !key.isFunctional && key.primaryLabel.length == 1) {
            Popup(
                alignment = Alignment.TopCenter,
                offset = IntOffset(0, -130),
                properties = PopupProperties(focusable = false)
            ) {
                Surface(
                    shape = RoundedCornerShape(8.dp),
                    color = Color(palette.keycapColor),
                    shadowElevation = 6.dp,
                    border = androidx.compose.foundation.BorderStroke(1.dp, Color(palette.borderColor)),
                    modifier = Modifier
                        .width(46.dp)
                        .height(54.dp)
                ) {
                    Box(contentAlignment = Alignment.Center) {
                        Text(
                            text = key.primaryLabel,
                            color = Color(palette.primaryTextColor),
                            fontSize = 24.sp,
                            fontWeight = FontWeight.Bold
                        )
                    }
                }
            }
        }

        // Long-Press Variant Options Popup
        if (showVariantsPopup && variantOptions.isNotEmpty()) {
            Popup(
                alignment = Alignment.TopCenter,
                offset = IntOffset(0, -120),
                onDismissRequest = { showVariantsPopup = false }
            ) {
                Surface(
                    shape = RoundedCornerShape(8.dp),
                    color = Color(palette.keycapColor),
                    shadowElevation = 8.dp,
                    border = androidx.compose.foundation.BorderStroke(1.dp, Color(palette.borderColor))
                ) {
                    Row(modifier = Modifier.padding(4.dp)) {
                        variantOptions.forEach { variant ->
                            Box(
                                modifier = Modifier
                                    .padding(horizontal = 6.dp, vertical = 4.dp)
                                    .clickable(
                                        interactionSource = remember { MutableInteractionSource() },
                                        indication = null
                                    ) {
                                        onKeyPressed(KeyAction.CommitChar(variant))
                                        showVariantsPopup = false
                                    },
                                contentAlignment = Alignment.Center
                            ) {
                                Text(
                                    text = variant,
                                    fontSize = 20.sp,
                                    fontWeight = FontWeight.Medium,
                                    color = Color(palette.primaryTextColor)
                                )
                            }
                        }
                    }
                }
            }
        }
    }
}

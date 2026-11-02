package com.tuyenmai.openkey.core

import java.util.concurrent.CopyOnWriteArrayList

/**
 * Immutable UI state observed by KeyboardScreen (REQ-011, ADR-011).
 */
data class EditorUiState(
    val enterActionLabel: String = "↵",
    val imeActionId: Int = InputContextEvaluator.IME_ACTION_UNSPECIFIED,
    val shouldSendNewlineOnEnter: Boolean = false,
    val bypassVietnamese: Boolean = false,
    val isSecureField: Boolean = false,
    val language: Int = 1,
    val packageName: String = ""
)

/**
 * Unified 120Hz session coordinator in :openkey-core (REQ-011, REQ-012, ADR-011, ADR-012).
 * Centralizes keystroke routing, EditorInfo evaluation, SmartSwitchStore per-app language,
 * BatchReplacementCoordinator atomic commits, and candidate selection for touch inputs.
 */
class KeyboardSessionController(
    val settingsStore: OpenKeySettingsStore = OpenKeySettingsStore(InMemoryKeyValueStorage()),
    val smartSwitchStore: SmartSwitchStore = SmartSwitchStore(InMemoryKeyValueStorage()),
    var committer: TextCommitterTarget? = null,
    val batchCoordinator: BatchReplacementCoordinator = BatchReplacementCoordinator(),
    val autoWordingEngine: AutoWordingEngine = AutoWordingEngine.shared
) {

    var editorUiState: EditorUiState = EditorUiState(language = settingsStore.language)
        private set

    private val uiStateListeners = CopyOnWriteArrayList<(EditorUiState) -> Unit>()

    init {
        editorUiState = EditorUiState(language = settingsStore.language)
        settingsStore.addListener { key ->
            if (key == OpenKeySettingsStore.KEY_LANGUAGE) {
                if (editorUiState.language != settingsStore.language) {
                    updateEditorUiState(editorUiState.copy(language = settingsStore.language))
                }
            }
        }
    }

    fun addUiStateListener(listener: (EditorUiState) -> Unit) {
        uiStateListeners.add(listener)
        listener(editorUiState)
    }

    fun removeUiStateListener(listener: (EditorUiState) -> Unit) {
        uiStateListeners.remove(listener)
    }

    private fun updateEditorUiState(newState: EditorUiState) {
        editorUiState = newState
        for (listener in uiStateListeners) {
            listener(newState)
        }
    }

    /**
     * Called on IME startInput / onStartInputView to evaluate context and publish reactive EditorUiState.
     */
    fun onStartInput(context: EditorContext, initialSelStart: Int = 0, initialSelEnd: Int = 0) {
        VietnameseEngine.resetSession()
        autoWordingEngine.clearCandidates()

        val eval = InputContextEvaluator.evaluate(context)
        val appLang = if (settingsStore.useSmartSwitchKey) {
            val resolved = smartSwitchStore.onAppSwitched(
                packageName = context.packageName,
                currentGlobalLanguage = settingsStore.language,
                useSmartSwitchKey = true
            )
            settingsStore.language = resolved
            resolved
        } else {
            settingsStore.language
        }

        batchCoordinator.resetExpectedCursor(initialSelStart, initialSelStart >= 0)

        val newState = EditorUiState(
            enterActionLabel = eval.enterActionLabel,
            imeActionId = eval.imeActionId,
            shouldSendNewlineOnEnter = eval.shouldSendNewlineOnEnter,
            bypassVietnamese = eval.bypassVietnamese,
            isSecureField = eval.isSecureField,
            language = appLang,
            packageName = context.packageName
        )
        updateEditorUiState(newState)
    }

    /**
     * Called when cursor / selection changes in framework.
     */
    fun onUpdateSelection(
        oldSelStart: Int,
        oldSelEnd: Int,
        newSelStart: Int,
        newSelEnd: Int
    ): Boolean {
        val resetOccurred = batchCoordinator.onUpdateSelection(oldSelStart, oldSelEnd, newSelStart, newSelEnd)
        if (resetOccurred) {
            autoWordingEngine.clearCandidates()
        }
        return resetOccurred
    }

    /**
     * Touch key action router executing the commit-first pipeline (REQ-011, REQ-012).
     */
    fun onKeyAction(action: KeyAction): Boolean {
        val target = committer ?: return false

        when (action) {
            is KeyAction.CommitChar -> {
                val charStr = action.char
                if (editorUiState.bypassVietnamese || editorUiState.language != 1) {
                    batchCoordinator.commitBatch(target, 0, charStr)
                    return true
                }

                if (charStr.length == 1) {
                    val ch = charStr[0]
                    val mapping = VietnameseData.charToKeyCode(ch)
                    val keyCode = mapping.first
                    val caps = mapping.second

                    if (keyCode == VietnameseData.KEY_EMPTY.toInt()) {
                        batchCoordinator.commitBatch(target, 0, charStr)
                        return true
                    }

                    VietnameseEngine.handleKeyEventCommitFirst(keyCode, caps, false) { snapshot ->
                        if (snapshot.code == HookCodeState.WILL_PROCESS ||
                            snapshot.code == HookCodeState.RESTORE ||
                            snapshot.code == HookCodeState.RESTORE_AND_START_NEW_SESSION
                        ) {
                            batchCoordinator.commitBatch(target, snapshot.backspaceCount, snapshot.decodedString)
                        } else {
                            batchCoordinator.commitBatch(target, 0, charStr)
                        }
                    }
                    return true
                } else {
                    batchCoordinator.commitBatch(target, 0, charStr)
                    return true
                }
            }

            is KeyAction.Backspace -> {
                if (editorUiState.bypassVietnamese || editorUiState.language != 1) {
                    target.deleteSurroundingText(1, 0)
                    batchCoordinator.onCursorMovedByTrackpad(-1)
                    VietnameseEngine.resetSession()
                    autoWordingEngine.clearCandidates()
                    return true
                }

                val keyCode = VietnameseData.KEY_DELETE.toInt()
                VietnameseEngine.handleKeyEventCommitFirst(keyCode, 0, false) { snapshot ->
                    if (snapshot.code == HookCodeState.WILL_PROCESS ||
                        snapshot.code == HookCodeState.RESTORE ||
                        snapshot.code == HookCodeState.RESTORE_AND_START_NEW_SESSION
                    ) {
                        batchCoordinator.commitBatch(target, snapshot.backspaceCount, snapshot.decodedString)
                    } else {
                        target.deleteSurroundingText(1, 0)
                        batchCoordinator.onCursorMovedByTrackpad(-1)
                    }
                }
                return true
            }

            is KeyAction.Space -> {
                if (editorUiState.bypassVietnamese || editorUiState.language != 1) {
                    batchCoordinator.commitBatch(target, 0, " ")
                    VietnameseEngine.resetSession()
                    autoWordingEngine.clearCandidates()
                    return true
                }

                val keyCode = VietnameseData.KEY_SPACE.toInt()
                VietnameseEngine.handleKeyEventCommitFirst(keyCode, 0, false) { snapshot ->
                    if (snapshot.code == HookCodeState.WILL_PROCESS ||
                        snapshot.code == HookCodeState.RESTORE ||
                        snapshot.code == HookCodeState.RESTORE_AND_START_NEW_SESSION
                    ) {
                        batchCoordinator.commitBatch(target, snapshot.backspaceCount, snapshot.decodedString)
                    } else {
                        batchCoordinator.commitBatch(target, 0, " ")
                    }
                }
                return true
            }

            is KeyAction.Enter -> {
                VietnameseEngine.resetSession()
                autoWordingEngine.clearCandidates()
                if (editorUiState.shouldSendNewlineOnEnter) {
                    batchCoordinator.commitBatch(target, 0, "\n")
                } else {
                    target.performEditorAction(editorUiState.imeActionId)
                }
                return true
            }

            is KeyAction.SwitchLanguage -> {
                val nextLang = if (editorUiState.language == 1) 0 else 1
                settingsStore.language = nextLang
                if (editorUiState.packageName.isNotBlank()) {
                    smartSwitchStore.setAppLanguage(editorUiState.packageName, nextLang)
                }
                VietnameseEngine.resetSession()
                autoWordingEngine.clearCandidates()
                updateEditorUiState(editorUiState.copy(language = nextLang))
                return true
            }

            is KeyAction.Shift,
            is KeyAction.SwitchLayer -> {
                return true
            }
        }
    }

    /**
     * Candidate selection handling.
     */
    fun onCandidateSelected(candidate: WordCandidate): Boolean {
        val target = committer ?: return false
        batchCoordinator.commitBatch(target, candidate.replaceLength, candidate.text + " ")
        autoWordingEngine.recordCandidateAcceptance(candidate.text)
        VietnameseEngine.resetSession()
        val nextCands = autoWordingEngine.computeNextWordCandidates(candidate.text)
        autoWordingEngine.updateCandidates(nextCands)
        return true
    }

    /**
     * Spacebar trackpad horizontal cursor dragging with zero IPC text extractions (REQ-013, ADR-013).
     */
    fun onMoveCursor(deltaChars: Int): Boolean {
        val target = committer ?: return false
        return target.moveCursorBy(deltaChars)
    }

    /**
     * Swipe left on backspace word deletion.
     */
    fun onDeletePreviousWord(): Boolean {
        val target = committer ?: return false
        VietnameseEngine.resetSession()
        autoWordingEngine.clearCandidates()
        return target.deletePreviousWord()
    }
}

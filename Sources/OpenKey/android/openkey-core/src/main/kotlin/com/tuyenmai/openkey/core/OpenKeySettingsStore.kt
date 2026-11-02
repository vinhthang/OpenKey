package com.tuyenmai.openkey.core

class OpenKeySettingsStore(private val storage: KeyValueStorage) {

    companion object {
        const val KEY_LANGUAGE = "setting_language"
        const val KEY_INPUT_TYPE = "setting_input_type"
        const val KEY_USE_MODERN_ORTHOGRAPHY = "setting_use_modern_orthography"
        const val KEY_CHECK_SPELLING = "setting_check_spelling"
        const val KEY_RESTORE_IF_WRONG_SPELLING = "setting_restore_if_wrong_spelling"
        const val KEY_BILINGUAL_AUTO_RESTORE = "setting_bilingual_auto_restore"
        const val KEY_USE_SMART_SWITCH_KEY = "setting_use_smart_switch_key"
        const val KEY_SHOW_NUMBER_ROW = "setting_show_number_row"
        const val KEY_HEIGHT_SCALE_PERCENT = "setting_height_scale_percent"
        const val KEY_BOTTOM_CHIN_PADDING_DP = "setting_bottom_chin_padding_dp"
        const val KEY_ONE_HANDED_MODE = "setting_one_handed_mode"
        const val KEY_HAPTIC_FEEDBACK_ENABLED = "setting_haptic_feedback_enabled"
        const val KEY_KEY_POPUP_PREVIEW_ENABLED = "setting_key_popup_preview_enabled"
        const val KEY_AUTO_WORDING_ENABLED = "setting_auto_wording_enabled"
        const val KEY_GRAMMAR_REPAIR_ENABLED = "setting_grammar_repair_enabled"
        const val KEY_SHORTHAND_EXPANSION_ENABLED = "setting_shorthand_expansion_enabled"
        const val KEY_CANDIDATE_SUGGESTIONS_ENABLED = "setting_candidate_suggestions_enabled"
        const val KEY_DOUBLE_SPACE_PERIOD_ENABLED = "setting_double_space_period_enabled"
        const val KEY_CUSTOM_SHORTHANDS = "setting_custom_shorthands"
    }

    private val listeners = mutableListOf<(String) -> Unit>()

    @Synchronized
    fun addListener(listener: (String) -> Unit) {
        listeners.add(listener)
    }

    @Synchronized
    fun removeListener(listener: (String) -> Unit) {
        listeners.remove(listener)
    }

    private fun notifyChanged(key: String) {
        val currentListeners = synchronized(this) { listeners.toList() }
        for (listener in currentListeners) {
            listener(key)
        }
    }

    var language: Int
        get() = storage.getInt(KEY_LANGUAGE, 1)
        set(value) {
            storage.putInt(KEY_LANGUAGE, value)
            notifyChanged(KEY_LANGUAGE)
        }

    var inputType: Int
        get() = storage.getInt(KEY_INPUT_TYPE, 0)
        set(value) {
            val clamped = value.coerceIn(0, 1)
            storage.putInt(KEY_INPUT_TYPE, clamped)
            notifyChanged(KEY_INPUT_TYPE)
        }

    var useModernOrthography: Boolean
        get() = storage.getBoolean(KEY_USE_MODERN_ORTHOGRAPHY, true)
        set(value) {
            storage.putBoolean(KEY_USE_MODERN_ORTHOGRAPHY, value)
            notifyChanged(KEY_USE_MODERN_ORTHOGRAPHY)
        }

    var checkSpelling: Boolean
        get() = storage.getBoolean(KEY_CHECK_SPELLING, true)
        set(value) {
            storage.putBoolean(KEY_CHECK_SPELLING, value)
            notifyChanged(KEY_CHECK_SPELLING)
        }

    var restoreIfWrongSpelling: Boolean
        get() = storage.getBoolean(KEY_RESTORE_IF_WRONG_SPELLING, true)
        set(value) {
            storage.putBoolean(KEY_RESTORE_IF_WRONG_SPELLING, value)
            notifyChanged(KEY_RESTORE_IF_WRONG_SPELLING)
        }

    var bilingualAutoRestore: Boolean
        get() = storage.getBoolean(KEY_BILINGUAL_AUTO_RESTORE, true)
        set(value) {
            storage.putBoolean(KEY_BILINGUAL_AUTO_RESTORE, value)
            notifyChanged(KEY_BILINGUAL_AUTO_RESTORE)
        }

    var useSmartSwitchKey: Boolean
        get() = storage.getBoolean(KEY_USE_SMART_SWITCH_KEY, true)
        set(value) {
            storage.putBoolean(KEY_USE_SMART_SWITCH_KEY, value)
            notifyChanged(KEY_USE_SMART_SWITCH_KEY)
        }

    var showNumberRow: Boolean
        get() = storage.getBoolean(KEY_SHOW_NUMBER_ROW, true)
        set(value) {
            storage.putBoolean(KEY_SHOW_NUMBER_ROW, value)
            notifyChanged(KEY_SHOW_NUMBER_ROW)
        }

    var heightScalePercent: Int
        get() = storage.getInt(KEY_HEIGHT_SCALE_PERCENT, 100)
        set(value) {
            val clamped = value.coerceIn(85, 125)
            storage.putInt(KEY_HEIGHT_SCALE_PERCENT, clamped)
            notifyChanged(KEY_HEIGHT_SCALE_PERCENT)
        }

    var bottomChinPaddingDp: Int
        get() = storage.getInt(KEY_BOTTOM_CHIN_PADDING_DP, 14)
        set(value) {
            val clamped = value.coerceIn(0, 48)
            storage.putInt(KEY_BOTTOM_CHIN_PADDING_DP, clamped)
            notifyChanged(KEY_BOTTOM_CHIN_PADDING_DP)
        }

    var oneHandedMode: OneHandedMode
        get() {
            val name = storage.getString(KEY_ONE_HANDED_MODE, OneHandedMode.OFF.name)
            return try {
                OneHandedMode.valueOf(name)
            } catch (e: Exception) {
                OneHandedMode.OFF
            }
        }
        set(value) {
            storage.putString(KEY_ONE_HANDED_MODE, value.name)
            notifyChanged(KEY_ONE_HANDED_MODE)
        }

    var hapticFeedbackEnabled: Boolean
        get() = storage.getBoolean(KEY_HAPTIC_FEEDBACK_ENABLED, true)
        set(value) {
            storage.putBoolean(KEY_HAPTIC_FEEDBACK_ENABLED, value)
            notifyChanged(KEY_HAPTIC_FEEDBACK_ENABLED)
        }

    var keyPopupPreviewEnabled: Boolean
        get() = storage.getBoolean(KEY_KEY_POPUP_PREVIEW_ENABLED, true)
        set(value) {
            storage.putBoolean(KEY_KEY_POPUP_PREVIEW_ENABLED, value)
            notifyChanged(KEY_KEY_POPUP_PREVIEW_ENABLED)
        }

    var grammarRepairEnabled: Boolean
        get() = storage.getBoolean(KEY_GRAMMAR_REPAIR_ENABLED, true)
        set(value) {
            storage.putBoolean(KEY_GRAMMAR_REPAIR_ENABLED, value)
            notifyChanged(KEY_GRAMMAR_REPAIR_ENABLED)
        }

    var shorthandExpansionEnabled: Boolean
        get() = storage.getBoolean(KEY_SHORTHAND_EXPANSION_ENABLED, true)
        set(value) {
            storage.putBoolean(KEY_SHORTHAND_EXPANSION_ENABLED, value)
            notifyChanged(KEY_SHORTHAND_EXPANSION_ENABLED)
        }

    var candidateSuggestionsEnabled: Boolean
        get() = storage.getBoolean(KEY_CANDIDATE_SUGGESTIONS_ENABLED, true)
        set(value) {
            storage.putBoolean(KEY_CANDIDATE_SUGGESTIONS_ENABLED, value)
            notifyChanged(KEY_CANDIDATE_SUGGESTIONS_ENABLED)
        }

    var doubleSpacePeriodEnabled: Boolean
        get() = storage.getBoolean(KEY_DOUBLE_SPACE_PERIOD_ENABLED, false)
        set(value) {
            storage.putBoolean(KEY_DOUBLE_SPACE_PERIOD_ENABLED, value)
            notifyChanged(KEY_DOUBLE_SPACE_PERIOD_ENABLED)
        }

    var autoWordingEnabled: Boolean
        get() = storage.getBoolean(KEY_AUTO_WORDING_ENABLED, true)
        set(value) {
            storage.putBoolean(KEY_AUTO_WORDING_ENABLED, value)
            if (value) {
                if (!grammarRepairEnabled && !shorthandExpansionEnabled && !candidateSuggestionsEnabled) {
                    grammarRepairEnabled = true
                    shorthandExpansionEnabled = true
                    candidateSuggestionsEnabled = true
                }
            }
            notifyChanged(KEY_AUTO_WORDING_ENABLED)
        }

    // Custom Shorthands
    fun getCustomShorthands(): Map<String, String> {
        val raw = storage.getString(KEY_CUSTOM_SHORTHANDS, "")
        if (raw.isBlank()) return emptyMap()

        val map = mutableMapOf<String, String>()
        val lines = raw.split("\n")
        for (line in lines) {
            val parts = line.split("\t", limit = 2)
            if (parts.size == 2) {
                map[parts[0]] = parts[1]
            }
        }
        return map
    }

    fun setCustomShorthand(shortcut: String, expansion: String) {
        val current = getCustomShorthands().toMutableMap()
        current[shortcut] = expansion
        persistShorthands(current)
    }

    fun removeCustomShorthand(shortcut: String) {
        val current = getCustomShorthands().toMutableMap()
        current.remove(shortcut)
        persistShorthands(current)
    }

    fun clearCustomShorthands() {
        storage.remove(KEY_CUSTOM_SHORTHANDS)
        notifyChanged(KEY_CUSTOM_SHORTHANDS)
    }

    private fun persistShorthands(map: Map<String, String>) {
        val serialized = map.entries.joinToString("\n") { "${it.key}\t${it.value}" }
        storage.putString(KEY_CUSTOM_SHORTHANDS, serialized)
        notifyChanged(KEY_CUSTOM_SHORTHANDS)
    }
}

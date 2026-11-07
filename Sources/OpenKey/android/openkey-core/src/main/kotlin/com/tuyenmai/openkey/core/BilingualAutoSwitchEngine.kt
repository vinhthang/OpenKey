package com.tuyenmai.openkey.core

data class PreviousWordEntry(
    var rawString: String,
    var composedString: String,
    var rawKeys: List<UInt>,
    var composedWord: List<UInt>,
    var wasRestoredToEnglish: Boolean
)

data class AutoRestoreUndoSnapshot(
    var originalComposedString: String,
    var originalTypingWord: List<UInt>,
    var originalIndex: Int,
    var originalKeyStates: List<UInt>,
    var originalStateIndex: Int,
    var replacedLengthOnScreen: Int,
    var rawLowerWord: String
)

data class NavSavedSnapshot(
    var typingWord: List<UInt>,
    var index: Int,
    var keyStates: List<UInt>,
    var stateIndex: Int,
    var rawKeyStates: List<UInt>,
    var rawStateIndex: Int,
    var droppedKeys: List<Pair<UInt, Int>>,
    var tempDisableKey: Boolean,
    var hasDigitPrefix: Boolean
)

object BilingualAutoSwitchEngine {

    fun stringToTargetKeys(str: String): List<UInt> {
        val keys = mutableListOf<UInt>()
        for (ch in str) {
            val mapping = VietnameseData.charToKeyCode(ch)
            val keyCode = mapping.first
            val caps = mapping.second
            if (keyCode != KEY_EMPTY.toInt()) {
                keys.add(keyCode.toUInt() or (if (caps != 0) CAPS_MASK else 0u))
            } else {
                keys.add(ch.code.toUInt() or PURE_CHARACTER_MASK)
            }
        }
        return keys
    }

    fun countVowelGroups(keys: List<UInt>): Int {
        val vowelKeyCodes = setOf(KEY_A, KEY_E, KEY_I, KEY_O, KEY_U, KEY_Y)
        var groups = 0
        var inVowel = false
        for (k in keys) {
            val base = (k and CHAR_MASK).toUShort()
            if (vowelKeyCodes.contains(base)) {
                if (!inVowel) {
                    groups++
                    inVowel = true
                }
            } else {
                inVowel = false
            }
        }
        return groups
    }

    fun effectiveLanguagePriority(state: VietnameseEngineState): LanguagePriority {
        val last = state.previousWords.lastOrNull()
        if (last != null) {
            return if (last.wasRestoredToEnglish) LanguagePriority.ENGLISH_FIRST else LanguagePriority.VIETNAMESE_FIRST
        }
        if (state.consecutiveEnglishWordCount > 0) {
            return LanguagePriority.ENGLISH_FIRST
        }
        return if (state.vLanguage == 1) LanguagePriority.VIETNAMESE_FIRST else LanguagePriority.ENGLISH_FIRST
    }

    fun evaluateWordBreakRestore(
        state: VietnameseEngineState,
        breakKeyCode: UShort,
        handleCode: Int
    ): Boolean {
        if (state.index <= 0 || state.stateIndex <= 0) return false
        val dict = VietnameseDictionary.shared

        val fullKeys = state.rawKeyStates.slice(0 until state.rawStateIndex)
        val fullChars = StringBuilder()
        for (k in fullKeys) {
            val c = VietnameseData.keyCodeToCharacter(k)
            if (c != 0.toUShort()) fullChars.append(c.toInt().toChar())
        }
        val fullRawStr = fullChars.toString()
        val fullRawLower = fullRawStr.lowercase()

        val stdRawKeys = state.keyStates.slice(0 until state.stateIndex)
        val stdChars = StringBuilder()
        for (k in stdRawKeys) {
            val c = VietnameseData.keyCodeToCharacter(k)
            if (c != 0.toUShort()) stdChars.append(c.toInt().toChar())
        }
        val stdRawStr = stdChars.toString()
        val stdRawLower = stdRawStr.lowercase()

        val compChars = StringBuilder()
        var hasAnyDiacritic = false
        var capitalCount = 0
        for (i in 0 until state.index) {
            if (state.typingWord[i].hasAnyDiacritic) hasAnyDiacritic = true
            if (state.typingWord[i].isCaps) capitalCount++
            val code = state.GET(state.typingWord[i])
            val valChar: UShort = if ((code and CHAR_CODE_MASK) != 0u || (code and PURE_CHARACTER_MASK) != 0u) {
                (code and 0xFFFFu).toUShort()
            } else {
                VietnameseData.keyCodeToCharacter(code)
            }
            if (valChar != 0.toUShort()) compChars.append(valChar.toInt().toChar())
        }
        val composed = compChars.toString()
        val composedLower = composed.lowercase()

        // Vietnamese Đ-acronyms ("VĐV", "BĐS", "HĐND") must never be restored
        val vowelKeySet = setOf(KEY_A, KEY_E, KEY_I, KEY_O, KEY_U, KEY_Y)
        val hasStrokeD = (0 until state.index).any { state.CHR(it) == KEY_D && state.typingWord[it].hasCircumflexOrStroke }
        val hasNoVowel = (0 until state.index).none { vowelKeySet.contains(state.CHR(it)) }
        val isVietnameseDAcronym = hasStrokeD && hasNoVowel && capitalCount >= 2
        if (isVietnameseDAcronym) {
            state.consecutiveEnglishWordCount = 0
            state.previousWords.clear()
            return false
        }

        // Single-backspace undo lock
        state.undoneRawWord?.let { locked ->
            if (locked == fullRawLower || locked == stdRawLower) {
                if (breakKeyCode == KEY_SPACE) state.undoneRawWord = null
                return false
            }
            state.undoneRawWord = null
        }

        val rawCapitalCount = fullKeys.count { (it and CAPS_MASK) != 0u }
        val singleToneLower = if (fullRawLower.isNotEmpty()) fullRawLower.dropLast(1) else ""
        val isTrailingDoubledToneEscape: Boolean = if (fullKeys.size >= 3) {
            val lastKey = (fullKeys[fullKeys.size - 1] and CHAR_MASK).toUShort()
            val prevKey = (fullKeys[fullKeys.size - 2] and CHAR_MASK).toUShort()
            lastKey == prevKey && state.isMarkKey(lastKey) && !dict.isEnglishWord(fullRawLower) && dict.isEnglishWord(singleToneLower)
        } else {
            false
        }

        if (isTrailingDoubledToneEscape && composedLower == singleToneLower) {
            if (breakKeyCode == KEY_SPACE) {
                state.previousWords.add(
                    PreviousWordEntry(
                        rawString = composed,
                        composedString = composed,
                        rawKeys = fullKeys.dropLast(1),
                        composedWord = state.typingWord.slice(0 until state.index),
                        wasRestoredToEnglish = true
                    )
                )
                if (state.previousWords.size > 2) state.previousWords.removeAt(0)
                state.consecutiveEnglishWordCount++
            }
            return false
        }

        val priority = effectiveLanguagePriority(state)
        val shouldCapitalizeSentence = state.sentenceEndedWithPunctuation &&
                AutoWordingEngine.shared.isEnabled &&
                AutoWordingEngine.shared.grammarRepairEnabled &&
                state.wordStartOk
        if (breakKeyCode == KEY_SPACE) {
            state.sentenceEndedWithPunctuation = false
        }

        // 1. Duplicate Word Collapse ("the the" -> "the")
        if (breakKeyCode == KEY_SPACE && state.previousWords.isNotEmpty()) {
            val prev = state.previousWords.last()
            val prevCompLower = prev.composedString.lowercase()
            val prevRawLower = prev.rawString.lowercase()
            if ((prevCompLower == fullRawLower || prevRawLower == fullRawLower) && dict.englishDuplicateCollapseWords.contains(fullRawLower)) {
                val targetWord = prev.rawString
                val totalBs = prev.composedString.length + 1 + state.index
                val keys = stringToTargetKeys(targetWord)
                state.hookOutput.code = handleCode
                state.hookOutput.backspaceCount = totalBs.coerceAtMost(255)
                state.hookOutput.newCharCount = keys.size.coerceAtMost(state.maxBuff)
                for (i in 0 until state.hookOutput.newCharCount) {
                    val k = keys[i]
                    state.hookOutput.charData[state.hookOutput.newCharCount - 1 - i] = if ((k and PURE_CHARACTER_MASK) != 0u) k else state.GET(k)
                    state.typingWord[i] = k
                    state.keyStates[i] = k
                }
                state.index = state.hookOutput.newCharCount
                state.stateIndex = state.index
                state.previousWords[state.previousWords.size - 1].composedString = targetWord
                state.previousWords[state.previousWords.size - 1].wasRestoredToEnglish = true
                state.tempDisableKey = false
                return true
            }
        }

        val isWordBreakKey = breakKeyCode == KEY_SPACE ||
                breakKeyCode == VietnameseData.KEY_COMMA ||
                breakKeyCode == VietnameseData.KEY_DOT ||
                breakKeyCode == VietnameseData.KEY_SLASH ||
                breakKeyCode == VietnameseData.KEY_SEMICOLON ||
                breakKeyCode == VietnameseData.KEY_QUOTE

        // 2. Bigram Grammar Corrections
        var replacementWord: String? = null
        if (isWordBreakKey && state.previousWords.isNotEmpty()) {
            val prevEntry = state.previousWords.last()
            val prevWord = prevEntry.composedString
            val cand1 = "${prevWord.lowercase()} $fullRawLower"
            val cand2 = "${prevWord.lowercase()} $composedLower"
            val matched = dict.englishBigramGrammar[cand1]
                ?: dict.englishBigramGrammar[cand2]
                ?: dict.vietnameseBigramGrammar[cand1]
                ?: dict.vietnameseBigramGrammar[cand2]

            if (matched != null) {
                val parts = matched.split(" ")
                if (parts.size == 2) {
                    val newPrev = parts[0]
                    val newCur = parts[1]
                    if (newPrev.lowercase() == prevWord.lowercase()) {
                        replacementWord = if (fullRawStr.firstOrNull()?.isUpperCase() == true) {
                            newCur.replaceFirstChar { it.uppercase() }
                        } else {
                            newCur
                        }
                    } else if (breakKeyCode == KEY_SPACE) {
                        val prevCap = prevWord.firstOrNull()?.isUpperCase() == true
                        val finalPrev = if (prevCap) newPrev.replaceFirstChar { it.uppercase() } else newPrev
                        val curCap = fullRawStr.firstOrNull()?.isUpperCase() == true
                        val finalCur = if (curCap) newCur.replaceFirstChar { it.uppercase() } else newCur
                        val combined = "$finalPrev $finalCur"
                        val totalBs = state.index + 1 + prevWord.length
                        val keys = stringToTargetKeys(combined)

                        state.hookOutput.code = handleCode
                        state.hookOutput.backspaceCount = totalBs.coerceAtMost(255)
                        state.hookOutput.newCharCount = keys.size.coerceAtMost(state.maxBuff)
                        for (i in 0 until state.hookOutput.newCharCount) {
                            val k = keys[i]
                            state.hookOutput.charData[state.hookOutput.newCharCount - 1 - i] = if ((k and PURE_CHARACTER_MASK) != 0u) k else state.GET(k)
                        }
                        state.previousWords[state.previousWords.size - 1].composedString = finalPrev
                        state.previousWords[state.previousWords.size - 1].rawString = finalPrev
                        state.previousWords.add(
                            PreviousWordEntry(
                                rawString = finalCur,
                                composedString = finalCur,
                                rawKeys = stringToTargetKeys(finalCur),
                                composedWord = stringToTargetKeys(finalCur),
                                wasRestoredToEnglish = true
                            )
                        )
                        if (state.previousWords.size > 2) state.previousWords.removeAt(0)
                        state.consecutiveEnglishWordCount++
                        state.startNewSessionInternal()
                        state.tempDisableKey = false
                        return true
                    }
                }
            }
        }

        // 3. English Contraction Grammar
        if (replacementWord == null) {
            dict.englishContractionGrammar[fullRawLower]?.let { contraction ->
                if (fullRawLower != "im" || priority == LanguagePriority.ENGLISH_FIRST) {
                    val isCap = fullRawStr.firstOrNull()?.isUpperCase() == true
                    replacementWord = if (isCap) contraction.replaceFirstChar { it.uppercase() } else contraction
                }
            }
        }

        // 4. Standalone "i" -> "I"
        if (replacementWord == null && breakKeyCode == KEY_SPACE) {
            if (fullRawStr == "i" && composed == "i" && (priority == LanguagePriority.ENGLISH_FIRST || !hasAnyDiacritic)) {
                replacementWord = "I"
            }
        }

        // 5. Typo & Transposition Corrections
        if (replacementWord == null) {
            if (priority == LanguagePriority.ENGLISH_FIRST) {
                val engMatch = if (!dict.isValidVietnameseSyllable(composedLower)) {
                    dict.englishTypoCorrections[fullRawLower] ?: dict.findEnglishTranspositionMatch(fullRawLower)
                } else null

                replacementWord = engMatch?.let { m ->
                    val isCap = fullRawStr.firstOrNull()?.isUpperCase() == true
                    if (isCap) m.replaceFirstChar { it.uppercase() } else m
                } ?: (dict.vietnameseTypoCorrections[composedLower] ?: dict.vietnameseTypoCorrections[fullRawLower])?.let { vnTypo ->
                    val isCap = composed.firstOrNull()?.isUpperCase() == true || fullRawStr.firstOrNull()?.isUpperCase() == true
                    if (isCap) vnTypo.replaceFirstChar { it.uppercase() } else vnTypo
                }
            } else {
                (dict.vietnameseTypoCorrections[composedLower] ?: dict.vietnameseTypoCorrections[fullRawLower])?.let { vnTypo ->
                    val isCap = composed.firstOrNull()?.isUpperCase() == true || fullRawStr.firstOrNull()?.isUpperCase() == true
                    replacementWord = if (isCap) vnTypo.replaceFirstChar { it.uppercase() } else vnTypo
                } ?: run {
                    if (!dict.isValidVietnameseSyllable(composedLower)) {
                        dict.englishTypoCorrections[fullRawLower]?.let { engTypo ->
                            val isCap = fullRawStr.firstOrNull()?.isUpperCase() == true
                            replacementWord = if (isCap) engTypo.replaceFirstChar { it.uppercase() } else engTypo
                        } ?: dict.findEnglishTranspositionMatch(fullRawLower)?.let { engTrans ->
                            val isCap = fullRawStr.firstOrNull()?.isUpperCase() == true
                            replacementWord = if (isCap) engTrans.replaceFirstChar { it.uppercase() } else engTrans
                        }
                    }
                }
            }
        }

        // 6. Sentence Capitalization
        if (shouldCapitalizeSentence && breakKeyCode == KEY_SPACE) {
            replacementWord?.let { rw ->
                replacementWord = rw.replaceFirstChar { it.uppercase() }
            } ?: run {
                val wordToCap = if ((dict.isEnglishWord(composedLower) && !hasAnyDiacritic) || (priority != LanguagePriority.ENGLISH_FIRST && dict.isValidVietnameseSyllable(composedLower))) composed else fullRawStr
                if (wordToCap.firstOrNull()?.isLowerCase() == true) {
                    replacementWord = wordToCap.replaceFirstChar { it.uppercase() }
                }
            }
        }

        val isTransformed = hasAnyDiacritic || composed != fullRawStr || isTrailingDoubledToneEscape
        var shouldRestore = false
        var targetKeys = fullKeys

        if (replacementWord == composed) replacementWord = null
        if (replacementWord != null) {
            shouldRestore = true
            targetKeys = stringToTargetKeys(replacementWord!!)
        } else if (dict.isEnglishWord(composedLower) && !hasAnyDiacritic) {
            // Composed word protection: e.g. "boss", "pass", "class", "off"
            shouldRestore = false
        } else if (isTransformed) {
            if (isTrailingDoubledToneEscape) {
                shouldRestore = true
                targetKeys = fullKeys.dropLast(1)
            } else if (!state.wordStartOk) {
                shouldRestore = true
                targetKeys = fullKeys
            } else if (state.droppedKeys.isNotEmpty() && dict.isEnglishWord(fullRawLower) && !dict.isEnglishWord(composedLower)) {
                shouldRestore = true
                targetKeys = fullKeys
            } else if (dict.englishPriorityWords.contains(fullRawLower)) {
                shouldRestore = true
                targetKeys = fullKeys
            } else if (priority == LanguagePriority.ENGLISH_FIRST && dict.isEnglishWord(fullRawLower)) {
                shouldRestore = true
                targetKeys = fullKeys
            } else if (dict.isEnglishWord(fullRawLower) && !dict.isValidVietnameseSyllable(composedLower)) {
                shouldRestore = true
                targetKeys = fullKeys
            } else if (rawCapitalCount >= 2) {
                shouldRestore = true
                targetKeys = fullKeys
            } else if (breakKeyCode == KEY_QUOTE && fullRawLower.endsWith("n")) {
                shouldRestore = true
                targetKeys = fullKeys
            } else if (breakKeyCode == KEY_MINUS && fullRawLower.startsWith("w")) {
                shouldRestore = true
                targetKeys = fullKeys
            } else if (state.hasDigitPrefix && !dict.isValidVietnameseSyllable(composedLower)) {
                shouldRestore = true
                targetKeys = fullKeys
            } else if (state.tempDisableKey && (hasAnyDiacritic || state.droppedKeys.isNotEmpty())) {
                shouldRestore = true
                targetKeys = if (dict.isEnglishWord(fullRawLower)) fullKeys else stdRawKeys
            }
        }

        val currentIsEnglish = shouldRestore || dict.englishPriorityWords.contains(fullRawLower) || (dict.isEnglishWord(fullRawLower) && !dict.isValidVietnameseSyllable(composedLower)) || fullRawLower in setOf("is", "as", "us", "if", "of", "or", "for", "his", "has", "was")

        // 1-2 word context look-back
        if (breakKeyCode == KEY_SPACE && currentIsEnglish && state.wordStartOk && state.previousWords.isNotEmpty()) {
            var firstRewriteIdx: Int? = null
            for (idx in state.previousWords.indices) {
                val prev = state.previousWords[idx]
                if (!prev.wasRestoredToEnglish && dict.englishLookbackStems.contains(prev.rawString.lowercase())) {
                    val allSubsequentEnglish = ((idx + 1) until state.previousWords.size).all { subIdx ->
                        val r = state.previousWords[subIdx].rawString.lowercase()
                        state.previousWords[subIdx].wasRestoredToEnglish || dict.isEnglishWord(r) || dict.englishLookbackStems.contains(r) || r == "a" || r == "i"
                    }
                    if (allSubsequentEnglish) {
                        firstRewriteIdx = idx
                        break
                    }
                }
            }

            if (firstRewriteIdx != null) {
                val startIdx = firstRewriteIdx
                var totalBackspace = state.index
                val combinedRawKeys = mutableListOf<UInt>()
                for (idx in startIdx until state.previousWords.size) {
                    totalBackspace += state.previousWords[idx].composedString.length + 1
                    combinedRawKeys.addAll(state.previousWords[idx].rawKeys)
                    combinedRawKeys.add(KEY_SPACE.toUInt())
                    state.previousWords[idx].wasRestoredToEnglish = true
                    state.previousWords[idx].composedString = state.previousWords[idx].rawString
                }
                val curKeys = if (shouldRestore) targetKeys else fullKeys
                combinedRawKeys.addAll(curKeys)

                if (combinedRawKeys.size <= 31) {
                    state.hookOutput.code = handleCode
                    state.hookOutput.backspaceCount = totalBackspace.coerceAtMost(255)
                    state.hookOutput.newCharCount = combinedRawKeys.size
                    for (i in 0 until combinedRawKeys.size) {
                        val k = combinedRawKeys[i]
                        state.hookOutput.charData[combinedRawKeys.size - 1 - i] = if (k == KEY_SPACE.toUInt()) {
                            0x20u or PURE_CHARACTER_MASK
                        } else if ((k and PURE_CHARACTER_MASK) != 0u) {
                            k
                        } else {
                            state.GET(k)
                        }
                    }
                    for (i in 0 until curKeys.size.coerceAtMost(state.maxBuff)) {
                        state.typingWord[i] = curKeys[i]
                        state.keyStates[i] = curKeys[i]
                    }
                    state.index = curKeys.size.coerceAtMost(state.maxBuff)
                    state.stateIndex = state.index
                    state.tempDisableKey = false

                    val targetChars = StringBuilder()
                    for (k in curKeys) {
                        if ((k and PURE_CHARACTER_MASK) != 0u) {
                            targetChars.append((k and 0xFFFFu).toInt().toChar())
                        } else {
                            val c = VietnameseData.keyCodeToCharacter(k)
                            if (c != 0.toUShort()) targetChars.append(c.toInt().toChar())
                        }
                    }
                    val restoredStr = targetChars.toString()
                    state.previousWords.add(
                        PreviousWordEntry(
                            rawString = restoredStr,
                            composedString = restoredStr,
                            rawKeys = curKeys,
                            composedWord = curKeys,
                            wasRestoredToEnglish = true
                        )
                    )
                    if (state.previousWords.size > 2) state.previousWords.removeAt(0)
                    state.consecutiveEnglishWordCount += 2
                    if (state.consecutiveEnglishWordCount >= 3) {
                        state.hookOutput.languageSwitchRequest = 0
                    }
                    return true
                }
            }
        }

        if (shouldRestore) {
            val origTypingWord = state.typingWord.slice(0 until state.index)
            val origKeyStates = state.keyStates.slice(0 until state.stateIndex)
            val origIndex = state.index
            val origStateIndex = state.stateIndex

            state.hookOutput.code = handleCode
            state.hookOutput.backspaceCount = state.index
            state.hookOutput.newCharCount = targetKeys.size.coerceAtMost(state.maxBuff)
            for (i in 0 until state.hookOutput.newCharCount) {
                state.typingWord[i] = targetKeys[i]
                state.keyStates[i] = targetKeys[i]
                val tk = targetKeys[i]
                state.hookOutput.charData[state.hookOutput.newCharCount - 1 - i] = if ((tk and PURE_CHARACTER_MASK) != 0u) tk else state.GET(state.typingWord[i])
            }
            state.index = state.hookOutput.newCharCount
            state.stateIndex = state.index
            state.tempDisableKey = false

            val targetChars = StringBuilder()
            for (k in targetKeys) {
                if ((k and PURE_CHARACTER_MASK) != 0u) {
                    targetChars.append((k and 0xFFFFu).toInt().toChar())
                } else {
                    val c = VietnameseData.keyCodeToCharacter(k)
                    if (c != 0.toUShort()) targetChars.append(c.toInt().toChar())
                }
            }
            val targetStr = targetChars.toString()

            val breakChar = VietnameseData.keyCodeToCharacter(breakKeyCode.toUInt() or (if (state.isCaps) CAPS_MASK else 0u))
            val trailingCount = if (breakChar != 0.toUShort()) 1 else 0
            val origComposed = if (replacementWord != null &&
                dict.vietnameseTypoCorrections[composedLower] == null &&
                dict.vietnameseBigramGrammar.values.none { it.endsWith(targetStr.lowercase()) }
            ) {
                fullRawStr
            } else {
                composed
            }

            state.autoRestoreUndoState = AutoRestoreUndoSnapshot(
                originalComposedString = origComposed,
                originalTypingWord = origTypingWord,
                originalIndex = origIndex,
                originalKeyStates = origKeyStates,
                originalStateIndex = origStateIndex,
                replacedLengthOnScreen = state.hookOutput.newCharCount + trailingCount,
                rawLowerWord = fullRawLower
            )

            val isEng = dict.isEnglishWord(targetStr.lowercase()) ||
                    dict.englishContractionGrammar.values.contains(targetStr) ||
                    targetStr == "I"
            if (breakKeyCode == KEY_SPACE) {
                state.previousWords.add(
                    PreviousWordEntry(
                        rawString = targetStr,
                        composedString = targetStr,
                        rawKeys = targetKeys,
                        composedWord = targetKeys,
                        wasRestoredToEnglish = isEng
                    )
                )
                if (state.previousWords.size > 2) state.previousWords.removeAt(0)
                if (isEng) {
                    state.consecutiveEnglishWordCount++
                    if (state.consecutiveEnglishWordCount >= 3) {
                        state.hookOutput.languageSwitchRequest = 0
                    }
                } else {
                    state.consecutiveEnglishWordCount = 0
                }
            } else {
                state.previousWords.clear()
                if (breakKeyCode == VietnameseData.KEY_COMMA && (isEng || !state.wordStartOk)) {
                    state.consecutiveEnglishWordCount += 1
                } else if (breakKeyCode != VietnameseData.KEY_COMMA || !isEng) {
                    state.consecutiveEnglishWordCount = 0
                }
            }
            return true
        } else {
            val vietnameseShorthandSet = setOf("ko", "dc", "vs", "vk", "ck", "mk", "nt", "nc", "bt", "bh", "uk", "uh", "ak", "ah")
            val isUnaccentedNonVn = !hasAnyDiacritic && composedLower.length >= 2 && !dict.isValidVietnameseSyllable(composedLower) && !vietnameseShorthandSet.contains(composedLower)
            val isComposedEng = (dict.isEnglishWord(composedLower) && !hasAnyDiacritic && (!dict.isValidVietnameseSyllable(composedLower) || dict.englishPriorityWords.contains(composedLower))) || composed == "I" || isUnaccentedNonVn
            val isEng = isComposedEng || (dict.isEnglishWord(fullRawLower) && !hasAnyDiacritic && (!dict.isValidVietnameseSyllable(composedLower) || dict.englishPriorityWords.contains(fullRawLower)))
            if (breakKeyCode == KEY_SPACE) {
                state.previousWords.add(
                    PreviousWordEntry(
                        rawString = if (isComposedEng) composed else fullRawStr,
                        composedString = composed,
                        rawKeys = if (isComposedEng) stdRawKeys else fullKeys,
                        composedWord = state.typingWord.slice(0 until state.index),
                        wasRestoredToEnglish = isEng
                    )
                )
                if (state.previousWords.size > 2) {
                    repeat(state.previousWords.size - 2) { state.previousWords.removeAt(0) }
                }
                if (isEng) {
                    state.consecutiveEnglishWordCount += 1
                    if (state.consecutiveEnglishWordCount >= 3) {
                        state.hookOutput.languageSwitchRequest = 0
                    }
                } else {
                    state.consecutiveEnglishWordCount = 0
                }
            } else {
                state.previousWords.clear()
                if (breakKeyCode == VietnameseData.KEY_COMMA && (isEng || !state.wordStartOk)) {
                    state.consecutiveEnglishWordCount += 1
                } else {
                    state.consecutiveEnglishWordCount = 0
                }
            }
            return false
        }
    }

    fun findEnglishTranspositionMatch(lower: String): String? {
        return VietnameseDictionary.shared.findEnglishTranspositionMatch(lower)
    }
}

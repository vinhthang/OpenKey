//
//  BilingualAutoSwitchEngine.swift
//  OpenKeySwiftCore
//
//  Intelligent Bilingual Auto-Switch, Dynamic Lexicon Prioritization,
//  and Context-Aware Grammar & Punctuation Engine (REQ-024, REQ-025, REQ-026, ADR-022..025).
//

import Foundation

public func OKEngineGetEffectiveLanguagePriority() -> LanguagePriority {
    let state = VietnameseEngineState.shared
    state.lock.lock()
    defer { state.lock.unlock() }
    return state.effectiveLanguagePriority()
}

// MARK: - Internal Session & Context Snapshots

struct PreviousWordEntry {
    var rawString: String
    var composedString: String
    var rawKeys: [UInt32]
    var composedWord: [UInt32]
    var wasRestoredToEnglish: Bool
}

struct AutoRestoreUndoSnapshot {
    var originalComposedString: String
    var originalTypingWord: [UInt32]
    var originalIndex: UInt8
    var originalKeyStates: [UInt32]
    var originalStateIndex: UInt8
    var replacedLengthOnScreen: Int
    var rawLowerWord: String
}

// MARK: - String to KeyCode Converter Helper

func stringToTargetKeys(_ str: String) -> [UInt32] {
    var keys: [UInt32] = []
    for ch in str {
        if let ascii = ch.asciiValue, let mapped = _characterMap[UInt32(ascii)] {
            keys.append(mapped)
        } else {
            for u in ch.utf16 {
                keys.append(UInt32(u) | PURE_CHARACTER_MASK)
            }
        }
    }
    return keys
}

// MARK: - Bilingual Engine Extension

extension VietnameseEngineState {
    
    nonisolated(unsafe) private static var enKeys: [UInt32] = []
    
    func effectiveLanguagePriority() -> LanguagePriority {
        if let last = previousWords.last {
            return last.wasRestoredToEnglish ? .englishFirst : .vietnameseFirst
        }
        if consecutiveEnglishWordCount > 0 {
            return .englishFirst
        }
        return (vLanguage == 1) ? .vietnameseFirst : .englishFirst
    }
    
    func isSentenceEndingPunctuation(_ codeWithFlags: UInt32) -> Bool {
        let charVal = keyCodeToCharacter(codeWithFlags)
        if charVal == UInt16(Character(".").asciiValue!) ||
           charVal == UInt16(Character("!").asciiValue!) ||
           charVal == UInt16(Character("?").asciiValue!) {
            return true
        }
        let base = UInt16(codeWithFlags & CHAR_MASK)
        let isCaps = (codeWithFlags & CAPS_MASK) != 0
        if base == KEY_DOT && !isCaps { return true }
        if base == KEY_1 && isCaps { return true }
        if base == KEY_SLASH && isCaps { return true }
        return false
    }
    
    func handleDoubleSpacePeriod() -> Bool {
        guard AutoWordingEngine.shared.isEnabled && AutoWordingEngine.shared.doubleSpacePeriodEnabled else { return false }
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastSpaceUptime <= 0.5 else { return false }
        guard !sentenceEndedWithPunctuation else { return false }
        guard specialChar.isEmpty else { return false }
        guard let lastWord = previousWords.last?.composedString, let lastChar = lastWord.last else { return false }
        guard lastChar.isLetter || lastChar.isNumber else { return false }
        
        hookOutput.code = HookCodeState.willProcess
        hookOutput.backspaceCount = 1
        hookOutput.newCharCount = 2
        hookOutput.extCode = 0
        hookOutput.charData[1] = UInt32(Character(".").asciiValue!) | PURE_CHARACTER_MASK
        hookOutput.charData[0] = UInt32(0x20) | PURE_CHARACTER_MASK
        
        sentenceEndedWithPunctuation = true
        spaceCount = 1
        specialChar.append(UInt32(KEY_DOT))
        saveSpecialChar()
        saveWord(keyCode: UInt32(KEY_SPACE), count: 1)
        lastSpaceUptime = now
        return true
    }
    
    func handleSingleBackspaceUndo() -> OKHookSnapshot? {
        guard let undo = autoRestoreUndoState else { return nil }
        autoRestoreUndoState = nil
        undoneRawWord = undo.rawLowerWord
        for i in 0..<maxBuff {
            typingWord[i] = (i < undo.originalTypingWord.count) ? undo.originalTypingWord[i] : UInt32(KEY_EMPTY)
            keyStates[i] = (i < undo.originalKeyStates.count) ? undo.originalKeyStates[i] : UInt32(KEY_EMPTY)
        }
        index = undo.originalIndex
        stateIndex = undo.originalStateIndex
        rawStateIndex = undo.originalStateIndex
        for i in 0..<rawKeyStates.count {
            rawKeyStates[i] = (i < Int(undo.originalStateIndex)) ? undo.originalKeyStates[i] : UInt32(KEY_EMPTY)
        }
        droppedKeys.removeAll()
        spaceCount = 0
        specialChar.removeAll()
        typingStates.removeAll()
        if !previousWords.isEmpty { previousWords.removeLast() }
        if consecutiveEnglishWordCount > 0 { consecutiveEnglishWordCount -= 1 }
        
        let utf16 = Array(undo.originalComposedString.utf16)
        return OKHookSnapshot(
            code: HookCodeState.willProcess,
            backspaceCount: UInt8(min(255, undo.replacedLengthOnScreen)),
            newCharCount: UInt8(min(255, utf16.count)),
            extCode: 2,
            shouldSendControlKey: false,
            utf16Chars: utf16,
            languageSwitchRequest: -1
        )
    }
    
    func checkRestoreIfWrongSpelling(handleCode: UInt8) -> Bool {
        return evaluateWordBreakRestore(breakKeyCode: KEY_SPACE, handleCode: handleCode)
    }
    
    func evaluateWordBreakRestore(breakKeyCode: UInt16, handleCode: UInt8) -> Bool {
        guard index > 0 && stateIndex > 0 else { return false }
        let dict = VietnameseDictionary.shared

        let fullKeys = Array(rawKeyStates[0..<Int(rawStateIndex)])
        let fullRawStr = keysToString(fullKeys)
        let fullRawLower = fullRawStr.lowercased()

        let stdRawKeys = Array(keyStates[0..<Int(stateIndex)])
        let stdRawLower = keysToString(stdRawKeys).lowercased()

        var compChars: [Character] = []
        var hasAnyDiacritic = false
        var capitalCount = 0
        for i in 0..<Int(index) {
            if typingWord[i].hasAnyDiacritic { hasAnyDiacritic = true }
            if typingWord[i].isCaps { capitalCount += 1 }
            let code = GET(typingWord[i])
            let val = ((code & CHAR_CODE_MASK) != 0 || (code & PURE_CHARACTER_MASK) != 0) ? UInt16(code & 0xFFFF) : keyCodeToCharacter(code)
            if let sc = UnicodeScalar(val), val != 0 { compChars.append(Character(sc)) }
        }
        let composed = String(compChars)
        let composedLower = composed.lowercased()

        let vowelKeySet: Set<UInt16> = [KEY_A, KEY_E, KEY_I, KEY_O, KEY_U, KEY_Y]
        let hasStrokeD = (0..<Int(index)).contains { CHR($0) == KEY_D && typingWord[$0].hasCircumflexOrStroke }
        let hasNoVowel = !(0..<Int(index)).contains { vowelKeySet.contains(CHR($0)) }
        if hasStrokeD && hasNoVowel && capitalCount >= 2 {
            consecutiveEnglishWordCount = 0
            previousWords.removeAll()
            return false
        }

        if let locked = undoneRawWord {
            if locked == fullRawLower || locked == stdRawLower {
                if breakKeyCode == KEY_SPACE { undoneRawWord = nil }
                return false
            }
            undoneRawWord = nil
        }

        let singleToneLower = fullRawLower.isEmpty ? "" : String(fullRawLower.dropLast())
        let isTrailingDoubledToneEscape = checkTrailingDoubledToneEscape(fullKeys: fullKeys, fullRawLower: fullRawLower, singleToneLower: singleToneLower, dict: dict)
        if isTrailingDoubledToneEscape && composedLower == singleToneLower {
            if breakKeyCode == KEY_SPACE { recordTrailingEscape(composed: composed, fullKeys: fullKeys) }
            return false
        }

        var bigramWord: String? = nil
        if AutoWordingEngine.shared.isEnabled && AutoWordingEngine.shared.grammarRepairEnabled {
            if tryCollapseDuplicateEnglishWord(breakKeyCode: breakKeyCode, handleCode: handleCode, fullRawLower: fullRawLower, dict: dict) {
                return true
            }

            let isWordBreakKey = isWordBreakKey(breakKeyCode)
            let (bgWord, rewroteBigram) = tryApplyBigramGrammar(breakKeyCode: breakKeyCode, handleCode: handleCode, fullRawLower: fullRawLower, composedLower: composedLower, fullRawStr: fullRawStr, isWordBreakKey: isWordBreakKey, dict: dict)
            if rewroteBigram { return true }
            bigramWord = bgWord
        }

        let priority = effectiveLanguagePriority()
        let replacementWord = resolveWordReplacement(breakKeyCode: breakKeyCode, priority: priority, fullRawStr: fullRawStr, fullRawLower: fullRawLower, stdRawLower: stdRawLower, composed: composed, composedLower: composedLower, fullKeys: fullKeys, hasAnyDiacritic: hasAnyDiacritic, bigramWord: bigramWord, dict: dict)

        let isTransformed = hasAnyDiacritic || composed != fullRawStr || isTrailingDoubledToneEscape
        let (shouldRestore, targetKeys) = shouldRestoreCurrentWord(breakKeyCode: breakKeyCode, priority: priority, fullRawLower: fullRawLower, stdRawLower: stdRawLower, composedLower: composedLower, fullRawStr: fullRawStr, hasAnyDiacritic: hasAnyDiacritic, isTransformed: isTransformed, isTrailingDoubledToneEscape: isTrailingDoubledToneEscape, fullKeys: fullKeys, replacementWord: replacementWord, dict: dict)

        let currentIsEnglish = isCurrentWordEnglish(shouldRestore: shouldRestore, replacementWord: replacementWord, fullRawLower: fullRawLower, composedLower: composedLower, dict: dict)
        if tryRewriteTwoWordLookback(breakKeyCode: breakKeyCode, currentIsEnglish: currentIsEnglish, shouldRestore: shouldRestore, targetKeys: targetKeys, fullKeys: fullKeys, handleCode: handleCode, dict: dict) {
            return true
        }

        if shouldRestore {
            return emitHookReplacement(handleCode: handleCode, targetKeys: targetKeys, replacementWord: replacementWord, composed: composed, composedLower: composedLower, fullRawStr: fullRawStr, fullRawLower: fullRawLower, breakKeyCode: breakKeyCode, dict: dict)
        } else {
            recordWordInSlidingWindow(breakKeyCode: breakKeyCode, composed: composed, fullRawStr: fullRawStr, stdRawKeys: stdRawKeys, fullKeys: fullKeys, hasAnyDiacritic: hasAnyDiacritic, composedLower: composedLower, fullRawLower: fullRawLower, dict: dict)
            return false
        }
    }
    
    private func keysToString(_ keys: [UInt32]) -> String {
        var chars: [Character] = []
        for k in keys {
            if (k & PURE_CHARACTER_MASK) != 0 {
                if let sc = UnicodeScalar(UInt16(k & 0xFFFF)) { chars.append(Character(sc)) }
            } else {
                let c = keyCodeToCharacter(k)
                if let sc = UnicodeScalar(c), c != 0 { chars.append(Character(sc)) }
            }
        }
        return String(chars)
    }

    private func applyCasing(_ word: String, isCap: Bool) -> String {
        if isCap, let first = word.first {
            return first.uppercased() + word.dropFirst()
        }
        return word
    }

    private func checkTrailingDoubledToneEscape(
        fullKeys: [UInt32],
        fullRawLower: String,
        singleToneLower: String,
        dict: VietnameseDictionary
    ) -> Bool {
        guard fullKeys.count >= 3 else { return false }
        let lastKey = UInt16(fullKeys[fullKeys.count - 1] & CHAR_MASK)
        let prevKey = UInt16(fullKeys[fullKeys.count - 2] & CHAR_MASK)
        return lastKey == prevKey && isMarkKey(lastKey) && !dict.isEnglishWord(fullRawLower) && dict.isEnglishWord(singleToneLower)
    }

    private func recordTrailingEscape(composed: String, fullKeys: [UInt32]) {
        previousWords.append(
            PreviousWordEntry(
                rawString: composed,
                composedString: composed,
                rawKeys: Array(fullKeys.dropLast()),
                composedWord: Array(typingWord[0..<Int(index)]),
                wasRestoredToEnglish: true
            )
        )
        if previousWords.count > 2 { previousWords.removeFirst(previousWords.count - 2) }
        consecutiveEnglishWordCount += 1
    }

    private func tryCollapseDuplicateEnglishWord(
        breakKeyCode: UInt16,
        handleCode: UInt8,
        fullRawLower: String,
        dict: VietnameseDictionary
    ) -> Bool {
        guard breakKeyCode == KEY_SPACE, let prev = previousWords.last else { return false }
        let prevCompLower = prev.composedString.lowercased()
        let prevRawLower = prev.rawString.lowercased()
        if (prevCompLower == fullRawLower || prevRawLower == fullRawLower) && dict.englishDuplicateCollapseWords.contains(fullRawLower) {
            let targetWord = prev.rawString
            let totalBs = prev.composedString.utf16.count + 1 + Int(index)
            let keys = stringToTargetKeys(targetWord)
            hookOutput.code = handleCode
            hookOutput.backspaceCount = UInt8(min(255, totalBs))
            hookOutput.newCharCount = UInt8(min(maxBuff, keys.count))
            for i in 0..<Int(hookOutput.newCharCount) {
                let k = keys[i]
                hookOutput.charData[Int(hookOutput.newCharCount) - 1 - i] = (k & PURE_CHARACTER_MASK) != 0 ? k : GET(k)
                typingWord[i] = k
                keyStates[i] = k
            }
            index = hookOutput.newCharCount
            stateIndex = index
            previousWords[previousWords.count - 1].composedString = targetWord
            previousWords[previousWords.count - 1].wasRestoredToEnglish = true
            tempDisableKey = false
            return true
        }
        return false
    }

    private func isWordBreakKey(_ breakKeyCode: UInt16) -> Bool {
        return breakKeyCode == KEY_SPACE || breakKeyCode == KEY_COMMA ||
               breakKeyCode == KEY_DOT || breakKeyCode == KEY_SLASH ||
               breakKeyCode == KEY_SEMICOLON || breakKeyCode == KEY_QUOTE
    }

    private func tryApplyBigramGrammar(
        breakKeyCode: UInt16,
        handleCode: UInt8,
        fullRawLower: String,
        composedLower: String,
        fullRawStr: String,
        isWordBreakKey: Bool,
        dict: VietnameseDictionary
    ) -> (replacementWord: String?, rewroteBigram: Bool) {
        guard isWordBreakKey, let prevEntry = previousWords.last else { return (nil, false) }
        let prevWord = prevEntry.composedString
        let cand1 = "\(prevWord.lowercased()) \(fullRawLower)"
        let cand2 = "\(prevWord.lowercased()) \(composedLower)"
        guard let matched = dict.englishBigramGrammar[cand1] ?? dict.englishBigramGrammar[cand2] ??
                            dict.vietnameseBigramGrammar[cand1] ?? dict.vietnameseBigramGrammar[cand2] else {
            return (nil, false)
        }
        let parts = matched.split(separator: " ").map(String.init)
        guard parts.count == 2 else { return (nil, false) }
        let newPrev = parts[0]
        let newCur = parts[1]
        if newPrev.lowercased() == prevWord.lowercased() {
            let replacementWord = applyCasing(newCur, isCap: fullRawStr.first?.isUppercase == true)
            return (replacementWord, false)
        } else if breakKeyCode == KEY_SPACE {
            let finalPrev = applyCasing(newPrev, isCap: prevWord.first?.isUppercase == true)
            let finalCur = applyCasing(newCur, isCap: fullRawStr.first?.isUppercase == true)
            let combined = "\(finalPrev) \(finalCur)"
            let totalBs = Int(index) + 1 + prevWord.utf16.count
            let keys = stringToTargetKeys(combined)
            
            hookOutput.code = handleCode
            hookOutput.backspaceCount = UInt8(min(255, totalBs))
            hookOutput.newCharCount = UInt8(min(maxBuff, keys.count))
            for i in 0..<Int(hookOutput.newCharCount) {
                let k = keys[i]
                hookOutput.charData[Int(hookOutput.newCharCount) - 1 - i] = (k & PURE_CHARACTER_MASK) != 0 ? k : GET(k)
            }
            previousWords[previousWords.count - 1].composedString = finalPrev
            previousWords[previousWords.count - 1].rawString = finalPrev
            previousWords.append(PreviousWordEntry(
                rawString: finalCur,
                composedString: finalCur,
                rawKeys: stringToTargetKeys(finalCur),
                composedWord: stringToTargetKeys(finalCur),
                wasRestoredToEnglish: true
            ))
            if previousWords.count > 2 { previousWords.removeFirst(previousWords.count - 2) }
            consecutiveEnglishWordCount += 1
            startNewSessionInternal()
            tempDisableKey = false
            return (nil, true)
        }
        return (nil, false)
    }

    private func resolveWordReplacement(
        breakKeyCode: UInt16,
        priority: LanguagePriority,
        fullRawStr: String,
        fullRawLower: String,
        stdRawLower: String,
        composed: String,
        composedLower: String,
        fullKeys: [UInt32],
        hasAnyDiacritic: Bool,
        bigramWord: String?,
        dict: VietnameseDictionary
    ) -> String? {
        guard AutoWordingEngine.shared.isEnabled && AutoWordingEngine.shared.grammarRepairEnabled else { return nil }
        var rw = bigramWord
        if rw == nil, let contraction = dict.englishContractionGrammar[fullRawLower] {
            if fullRawLower != "im" || priority == .englishFirst {
                rw = applyCasing(contraction, isCap: fullRawStr.first?.isUppercase == true)
            }
        }
        if rw == nil && breakKeyCode == KEY_SPACE && fullRawStr == "i" && composed == "i" &&
            (priority == .englishFirst || !hasAnyDiacritic) {
            rw = "I"
        }
        let rawCapCount = fullKeys.filter { ($0 & CAPS_MASK) != 0 }.count
        if rw == nil && rawCapCount < 2 && !(breakKeyCode == KEY_QUOTE && fullRawLower.hasSuffix("n")) {
            let prevWord = previousWords.last?.composedString
            let isCap = composed.first?.isUppercase == true || fullRawStr.first?.isUppercase == true
            let isBreakForTypo = (breakKeyCode == KEY_SPACE || breakKeyCode == KEY_COMMA)
            if priority == .englishFirst {
                let engMatch: String? = {
                    if !dict.isValidVietnameseSyllable(composedLower) {
                        return dict.englishTypoCorrections[fullRawLower] ?? dict.findEnglishTranspositionMatch(fullRawLower)
                    }
                    return nil
                }()
                if let em = engMatch {
                    rw = applyCasing(em, isCap: fullRawStr.first?.isUppercase == true)
                } else if let vnTypo = dict.vietnameseTypoCorrections[composedLower] ?? dict.vietnameseTypoCorrections[fullRawLower] {
                    rw = applyCasing(vnTypo, isCap: isCap)
                } else if isBreakForTypo && !dict.isValidVietnameseSyllable(composedLower) && !dict.isEnglishWord(fullRawLower) && !dict.isEnglishWord(composedLower) && !dict.isEnglishWord(stdRawLower) {
                    let sp = dict.findVietnameseSpatialMatch(fullRawLower, composedLower: composedLower, previousWord: prevWord)
                        ?? ((stdRawLower != fullRawLower && !dict.isEnglishWord(stdRawLower)) ? dict.findVietnameseSpatialMatch(stdRawLower, composedLower: composedLower, previousWord: prevWord) : nil)
                    if let sp = sp { rw = applyCasing(sp, isCap: isCap) }
                }
            } else {
                if let vnTypo = dict.vietnameseTypoCorrections[composedLower] ?? dict.vietnameseTypoCorrections[fullRawLower] {
                    rw = applyCasing(vnTypo, isCap: isCap)
                } else if let engTypo = dict.englishTypoCorrections[fullRawLower] {
                    rw = applyCasing(engTypo, isCap: fullRawStr.first?.isUppercase == true)
                } else if isBreakForTypo && !dict.isValidVietnameseSyllable(composedLower) && !dict.isEnglishWord(fullRawLower) && !dict.isEnglishWord(composedLower) && !dict.isEnglishWord(stdRawLower) {
                    let sp = dict.findVietnameseSpatialMatch(fullRawLower, composedLower: composedLower, previousWord: prevWord)
                        ?? ((stdRawLower != fullRawLower && !dict.isEnglishWord(stdRawLower)) ? dict.findVietnameseSpatialMatch(stdRawLower, composedLower: composedLower, previousWord: prevWord) : nil)
                    if let sp = sp {
                        rw = applyCasing(sp, isCap: isCap)
                    } else if let engTrans = dict.findEnglishTranspositionMatch(fullRawLower) {
                        rw = applyCasing(engTrans, isCap: fullRawStr.first?.isUppercase == true)
                    }
                }
            }
        }
        applySentenceCapitalization(rw: &rw, breakKeyCode: breakKeyCode, composed: composed, composedLower: composedLower, fullRawStr: fullRawStr, hasAnyDiacritic: hasAnyDiacritic, priority: priority, dict: dict)
        return (rw == composed) ? nil : rw
    }

    private func applySentenceCapitalization(
        rw: inout String?,
        breakKeyCode: UInt16,
        composed: String,
        composedLower: String,
        fullRawStr: String,
        hasAnyDiacritic: Bool,
        priority: LanguagePriority,
        dict: VietnameseDictionary
    ) {
        let shouldCapSentence = sentenceEndedWithPunctuation && AutoWordingEngine.shared.isEnabled &&
            AutoWordingEngine.shared.grammarRepairEnabled && wordStartOk
        if breakKeyCode == KEY_SPACE { sentenceEndedWithPunctuation = false }
        if shouldCapSentence && breakKeyCode == KEY_SPACE {
            if let existing = rw {
                rw = existing.prefix(1).uppercased() + existing.dropFirst()
            } else {
                let wordToCap = ((dict.isEnglishWord(composedLower) && !hasAnyDiacritic) || (priority != .englishFirst && dict.isValidVietnameseSyllable(composedLower))) ? composed : fullRawStr
                if wordToCap.first?.isLowercase == true {
                    rw = wordToCap.prefix(1).uppercased() + wordToCap.dropFirst()
                }
            }
        }
    }

    private func shouldRestoreCurrentWord(
        breakKeyCode: UInt16,
        priority: LanguagePriority,
        fullRawLower: String,
        stdRawLower: String,
        composedLower: String,
        fullRawStr: String,
        hasAnyDiacritic: Bool,
        isTransformed: Bool,
        isTrailingDoubledToneEscape: Bool,
        fullKeys: [UInt32],
        replacementWord: String?,
        dict: VietnameseDictionary
    ) -> (shouldRestore: Bool, targetKeys: [UInt32]) {
        let rawCapCount = fullKeys.filter { ($0 & CAPS_MASK) != 0 }.count
        if let rw = replacementWord {
            return (true, stringToTargetKeys(rw))
        } else if dict.isEnglishWord(composedLower) && !hasAnyDiacritic {
            return (false, fullKeys)
        } else if isTransformed {
            let restoreKeys: [UInt32]? = {
                if isTrailingDoubledToneEscape {
                    return Array(fullKeys.dropLast())
                } else if !wordStartOk {
                    return fullKeys
                } else if !droppedKeys.isEmpty && dict.isEnglishWord(fullRawLower) && !dict.isEnglishWord(composedLower) {
                    return fullKeys
                } else if dict.englishPriorityWords.contains(fullRawLower) {
                    return fullKeys
                } else if priority == .englishFirst && dict.isEnglishWord(fullRawLower) {
                    return fullKeys
                } else if dict.isEnglishWord(fullRawLower) && !dict.isValidVietnameseSyllable(composedLower) {
                    return fullKeys
                } else if rawCapCount >= 2 {
                    return fullKeys
                } else if breakKeyCode == KEY_QUOTE && fullRawLower.hasSuffix("n") {
                    return fullKeys
                } else if breakKeyCode == KEY_MINUS && fullRawLower.hasPrefix("w") {
                    return fullKeys
                } else if hasDigitPrefix && !dict.isValidVietnameseSyllable(composedLower) {
                    return fullKeys
                } else if tempDisableKey && (hasAnyDiacritic || !droppedKeys.isEmpty) {
                    return dict.isEnglishWord(fullRawLower) ? fullKeys : Array(keyStates[0..<Int(stateIndex)])
                }
                return nil
            }()
            if let rk = restoreKeys {
                return (true, rk)
            }
        }
        return (false, fullKeys)
    }

    private func isCurrentWordEnglish(
        shouldRestore: Bool,
        replacementWord: String?,
        fullRawLower: String,
        composedLower: String,
        dict: VietnameseDictionary
    ) -> Bool {
        let restoredIsEnglish = shouldRestore && (replacementWord == nil || dict.isEnglishWord(replacementWord!.lowercased()) || replacementWord == "I")
        return restoredIsEnglish || dict.englishPriorityWords.contains(fullRawLower) ||
            (dict.isEnglishWord(fullRawLower) && !dict.isValidVietnameseSyllable(composedLower)) ||
            ["is", "as", "us", "if", "of", "or", "for", "his", "has", "was"].contains(fullRawLower)
    }

    private func tryRewriteTwoWordLookback(
        breakKeyCode: UInt16,
        currentIsEnglish: Bool,
        shouldRestore: Bool,
        targetKeys: [UInt32],
        fullKeys: [UInt32],
        handleCode: UInt8,
        dict: VietnameseDictionary
    ) -> Bool {
        guard breakKeyCode == KEY_SPACE, currentIsEnglish, wordStartOk, !previousWords.isEmpty else { return false }
        var firstRewriteIdx: Int? = nil
        for idx in 0..<previousWords.count {
            let prev = previousWords[idx]
            if !prev.wasRestoredToEnglish && dict.englishLookbackStems.contains(prev.rawString.lowercased()) {
                let allSubsequentEnglish = ((idx + 1)..<previousWords.count).allSatisfy {
                    let r = previousWords[$0].rawString.lowercased()
                    return previousWords[$0].wasRestoredToEnglish || dict.isEnglishWord(r) || dict.englishLookbackStems.contains(r) || r == "a" || r == "i"
                }
                if allSubsequentEnglish {
                    firstRewriteIdx = idx
                    break
                }
            }
        }
        guard let startIdx = firstRewriteIdx else { return false }
        var totalBackspace = Int(index)
        var combinedRawKeys: [UInt32] = []
        for idx in startIdx..<previousWords.count {
            totalBackspace += previousWords[idx].composedString.utf16.count + 1
            combinedRawKeys.append(contentsOf: previousWords[idx].rawKeys)
            combinedRawKeys.append(UInt32(KEY_SPACE))
            previousWords[idx].wasRestoredToEnglish = true
            previousWords[idx].composedString = previousWords[idx].rawString
        }
        let curKeys = shouldRestore ? targetKeys : fullKeys
        combinedRawKeys.append(contentsOf: curKeys)
        guard combinedRawKeys.count <= 31 else { return false }

        hookOutput.code = handleCode
        hookOutput.backspaceCount = UInt8(min(255, totalBackspace))
        hookOutput.newCharCount = UInt8(combinedRawKeys.count)
        for i in 0..<combinedRawKeys.count {
            let k = combinedRawKeys[i]
            hookOutput.charData[combinedRawKeys.count - 1 - i] = (k == UInt32(KEY_SPACE)) ? (UInt32(0x20) | PURE_CHARACTER_MASK) : ((k & PURE_CHARACTER_MASK) != 0 ? k : GET(k))
        }
        for i in 0..<curKeys.count where i < maxBuff {
            typingWord[i] = curKeys[i]
            keyStates[i] = curKeys[i]
        }
        index = UInt8(min(maxBuff, curKeys.count))
        stateIndex = index
        tempDisableKey = false

        let restoredStr = keysToString(curKeys)
        previousWords.append(PreviousWordEntry(rawString: restoredStr, composedString: restoredStr, rawKeys: curKeys, composedWord: curKeys, wasRestoredToEnglish: true))
        if previousWords.count > 2 { previousWords.removeFirst(previousWords.count - 2) }
        consecutiveEnglishWordCount += 2
        if consecutiveEnglishWordCount >= 3 {
            hookOutput.languageSwitchRequest = 0
        }
        return true
    }

    private func emitHookReplacement(
        handleCode: UInt8,
        targetKeys: [UInt32],
        replacementWord: String?,
        composed: String,
        composedLower: String,
        fullRawStr: String,
        fullRawLower: String,
        breakKeyCode: UInt16,
        dict: VietnameseDictionary
    ) -> Bool {
        let origTypingWord = Array(typingWord[0..<Int(index)])
        let origKeyStates = Array(keyStates[0..<Int(stateIndex)])
        let origIndex = index
        let origStateIndex = stateIndex

        hookOutput.code = handleCode
        hookOutput.backspaceCount = index
        hookOutput.newCharCount = UInt8(min(maxBuff, targetKeys.count))
        for i in 0..<Int(hookOutput.newCharCount) {
            typingWord[i] = targetKeys[i]
            keyStates[i] = targetKeys[i]
            let tk = targetKeys[i]
            hookOutput.charData[Int(hookOutput.newCharCount) - 1 - i] = (tk & PURE_CHARACTER_MASK) != 0 ? tk : GET(typingWord[i])
        }
        index = hookOutput.newCharCount
        stateIndex = index
        tempDisableKey = false

        let targetStr = keysToString(targetKeys)
        let breakChar = keyCodeToCharacter(UInt32(breakKeyCode) | (isCaps ? CAPS_MASK : 0))
        let trailingCount = (breakChar != 0) ? 1 : 0
        let origComposed = (replacementWord != nil && dict.vietnameseTypoCorrections[composedLower] == nil &&
            dict.vietnameseBigramGrammar.values.allSatisfy({ !$0.hasSuffix(targetStr.lowercased()) })) ? fullRawStr : composed

        autoRestoreUndoState = AutoRestoreUndoSnapshot(
            originalComposedString: origComposed,
            originalTypingWord: origTypingWord,
            originalIndex: origIndex,
            originalKeyStates: origKeyStates,
            originalStateIndex: origStateIndex,
            replacedLengthOnScreen: Int(hookOutput.newCharCount) + trailingCount,
            rawLowerWord: fullRawLower
        )

        let isEng = dict.isEnglishWord(targetStr.lowercased()) || dict.englishContractionGrammar.values.contains(targetStr) || targetStr == "I"
        if breakKeyCode == KEY_SPACE {
            previousWords.append(PreviousWordEntry(
                rawString: targetStr,
                composedString: targetStr,
                rawKeys: targetKeys,
                composedWord: targetKeys,
                wasRestoredToEnglish: isEng
            ))
            if previousWords.count > 2 { previousWords.removeFirst(previousWords.count - 2) }
            if isEng {
                consecutiveEnglishWordCount += 1
                if consecutiveEnglishWordCount >= 3 {
                    hookOutput.languageSwitchRequest = 0
                }
            } else {
                consecutiveEnglishWordCount = 0
            }
        } else {
            previousWords.removeAll()
            if breakKeyCode == KEY_COMMA && (isEng || !wordStartOk) {
                consecutiveEnglishWordCount += 1
            } else if breakKeyCode != KEY_COMMA || !isEng {
                consecutiveEnglishWordCount = 0
            }
        }
        return true
    }

    private func recordWordInSlidingWindow(
        breakKeyCode: UInt16,
        composed: String,
        fullRawStr: String,
        stdRawKeys: [UInt32],
        fullKeys: [UInt32],
        hasAnyDiacritic: Bool,
        composedLower: String,
        fullRawLower: String,
        dict: VietnameseDictionary
    ) {
        let vietnameseShorthandSet: Set<String> = ["ko", "dc", "vs", "vk", "ck", "mk", "nt", "nc", "bt", "bh", "uk", "uh", "ak", "ah"]
        let isUnaccentedNonVn = !hasAnyDiacritic && composedLower.count >= 2 && !dict.isValidVietnameseSyllable(composedLower) && !vietnameseShorthandSet.contains(composedLower)
        let isComposedEng = (dict.isEnglishWord(composedLower) && !hasAnyDiacritic && (!dict.isValidVietnameseSyllable(composedLower) || dict.englishPriorityWords.contains(composedLower))) || composed == "I" || isUnaccentedNonVn
        let isEng = isComposedEng || (dict.isEnglishWord(fullRawLower) && !hasAnyDiacritic && (!dict.isValidVietnameseSyllable(composedLower) || dict.englishPriorityWords.contains(fullRawLower)))
        if breakKeyCode == KEY_SPACE {
            previousWords.append(PreviousWordEntry(
                rawString: isComposedEng ? composed : fullRawStr,
                composedString: composed,
                rawKeys: isComposedEng ? stdRawKeys : fullKeys,
                composedWord: Array(typingWord[0..<Int(index)]),
                wasRestoredToEnglish: isEng
            ))
            if previousWords.count > 2 { previousWords.removeFirst(previousWords.count - 2) }
            if isEng {
                consecutiveEnglishWordCount += 1
                if consecutiveEnglishWordCount >= 3 {
                    hookOutput.languageSwitchRequest = 0
                }
            } else {
                consecutiveEnglishWordCount = 0
            }
        } else {
            previousWords.removeAll()
            if breakKeyCode == KEY_COMMA && (isEng || !wordStartOk) {
                consecutiveEnglishWordCount += 1
            } else {
                consecutiveEnglishWordCount = 0
            }
        }
    }
    
    func handleEnglishModeKeyEvent(keyCode: UInt16, capsStatus: UInt8, otherControlKey: Bool) -> OKHookSnapshot {
        lock.lock()
        defer { lock.unlock() }
        
        if otherControlKey { Self.enKeys.removeAll(); wordStartOk = true; return OKHookSnapshot(code: HookCodeState.doNothing) }
        if keyCode == KEY_DELETE { if !Self.enKeys.isEmpty { Self.enKeys.removeLast() }; return OKHookSnapshot(code: HookCodeState.doNothing) }
        
        let isAlphaKey = !isNumberKey(keyCode) && !charKeyCode.contains(keyCode)
        let isBreak = breakCode.contains(keyCode) || keyCode == KEY_SPACE
        
        if !isBreak && isAlphaKey && Self.enKeys.count < maxBuff {
            let caps = (capsStatus == 1) || (capsStatus == 2 && isAlphaKey)
            Self.enKeys.append(UInt32(keyCode) | (caps ? CAPS_MASK : 0))
            return OKHookSnapshot(code: HookCodeState.doNothing)
        }
        
        if isBreak {
            let isCompoundSep = (keyCode == KEY_DOT || (keyCode == KEY_MINUS && capsStatus == 1) || keyCode == KEY_SLASH || (keyCode == KEY_2 && capsStatus == 1))
            let savedEnKeys = Self.enKeys
            let canReplay = wordStartOk && !savedEnKeys.isEmpty
            Self.enKeys.removeAll()
            wordStartOk = !isCompoundSep
            
            guard canReplay else {
                return OKHookSnapshot(code: HookCodeState.doNothing)
            }
            
            var rawChars: [Character] = []
            for entry in savedEnKeys {
                let c = keyCodeToCharacter(entry)
                if let sc = UnicodeScalar(c), c != 0 { rawChars.append(Character(sc)) }
            }
            let rawStr = String(rawChars)
            let rawLower = rawStr.lowercased()
            let dict = VietnameseDictionary.shared
            if dict.englishWords.contains(rawLower) || dict.englishPriorityWords.contains(rawLower) {
                return OKHookSnapshot(code: HookCodeState.doNothing)
            }
            
            clearBuffersInternal()
            for entry in savedEnKeys {
                let kCode = UInt16(entry & CHAR_MASK)
                let cStat: UInt8 = (entry & CAPS_MASK) != 0 ? 1 : 0
                isCaps = (cStat == 1)
                hookOutput.code = HookCodeState.doNothing
                insertState(keyCode: kCode, caps: isCaps)
                if !isSpecialKey(kCode) || tempDisableKey {
                    insertKey(keyCode: kCode, caps: isCaps)
                } else {
                    handleMainKey(data: kCode, caps: isCaps)
                }
                if !isKeyD(kCode) {
                    checkGrammar(deltaBackSpace: -1)
                }
                if hookOutput.code == HookCodeState.restore {
                    let swallowedEntry = UInt32(kCode) | (isCaps ? CAPS_MASK : 0)
                    droppedKeys.append((key: swallowedEntry, pos: Int(index)))
                    insertKey(keyCode: kCode, caps: isCaps)
                    if stateIndex > 0 { stateIndex -= 1 }
                }
            }
            checkSpelling(forceCheckVowel: true)
            let hasDiacritic = (0..<Int(index)).contains { typingWord[$0].hasAnyDiacritic }
            var composedChars: [Character] = []
            for i in 0..<Int(index) {
                let code = GET(typingWord[i])
                let val = ((code & CHAR_CODE_MASK) != 0 || (code & PURE_CHARACTER_MASK) != 0) ? UInt16(code & 0xFFFF) : keyCodeToCharacter(code)
                if let sc = UnicodeScalar(val), val != 0 { composedChars.append(Character(sc)) }
            }
            let composedStr = String(composedChars)
            clearBuffersInternal()
            
            if !tempDisableKey && hasDiacritic && dict.isValidVietnameseSyllable(composedStr) {
                vLanguage = 1
                consecutiveEnglishWordCount = 0
                var outUTF16 = Array(composedStr.utf16)
                var shouldSendCtrl = false
                let breakChar = keyCodeToCharacter(UInt32(keyCode) | ((capsStatus == 1) ? CAPS_MASK : 0))
                if breakChar != 0 {
                    outUTF16.append(breakChar)
                } else {
                    shouldSendCtrl = true
                }
                return OKHookSnapshot(
                    code: HookCodeState.willProcess,
                    backspaceCount: UInt8(min(255, savedEnKeys.count)),
                    newCharCount: UInt8(min(255, outUTF16.count)),
                    extCode: 1,
                    shouldSendControlKey: shouldSendCtrl,
                    utf16Chars: outUTF16,
                    languageSwitchRequest: 1
                )
            }
        } else {
            Self.enKeys.removeAll()
        }
        return OKHookSnapshot(code: HookCodeState.doNothing)
    }
}

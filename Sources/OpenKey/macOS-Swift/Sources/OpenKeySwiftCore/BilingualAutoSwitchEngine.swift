//
//  BilingualAutoSwitchEngine.swift
//  OpenKeySwiftCore
//
//  Intelligent Bilingual Auto-Switch, Dynamic Lexicon Prioritization,
//  and Context-Aware Grammar & Punctuation Engine (REQ-024, REQ-025, REQ-026, ADR-022..025).
//

import Foundation

// MARK: - Global Public Accessor

public enum BilingualAutoSwitchEngine {
    public static func findEnglishTranspositionMatch(_ lower: String) -> String? {
        VietnameseDictionary.shared.findEnglishTranspositionMatch(lower)
    }
}

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

struct NavSavedSnapshot {
    var typingWord: [UInt32]
    var index: UInt8
    var keyStates: [UInt32]
    var stateIndex: UInt8
    var rawKeyStates: [UInt32]
    var rawStateIndex: UInt8
    var droppedKeys: [(key: UInt32, pos: Int)]
    var tempDisableKey: Bool
    var hasDigitPrefix: Bool
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
    
    func handleArrowNavigationKey(keyCode: UInt16, capsStatus: UInt8) -> OKHookSnapshot? {
        if keyCode == KEY_LEFT && capsStatus == 0 {
            if index > 0 {
                navSavedState = NavSavedSnapshot(
                    typingWord: Array(typingWord[0..<Int(index)]),
                    index: index,
                    keyStates: Array(keyStates[0..<Int(stateIndex)]),
                    stateIndex: stateIndex,
                    rawKeyStates: Array(rawKeyStates[0..<Int(rawStateIndex)]),
                    rawStateIndex: rawStateIndex,
                    droppedKeys: droppedKeys,
                    tempDisableKey: tempDisableKey,
                    hasDigitPrefix: hasDigitPrefix
                )
            } else {
                navSavedState = nil
            }
            startNewSessionInternal()
            specialChar.removeAll()
            typingStates.removeAll()
            spaceCount = 0
            return buildOutputSnapshot(forKeyCode: keyCode)
        } else if keyCode == KEY_RIGHT && capsStatus == 0, let saved = navSavedState {
            navSavedState = nil
            clearBuffersInternal()
            for i in 0..<saved.typingWord.count { typingWord[i] = saved.typingWord[i] }
            index = saved.index
            for i in 0..<saved.keyStates.count { keyStates[i] = saved.keyStates[i] }
            stateIndex = saved.stateIndex
            for i in 0..<saved.rawKeyStates.count { rawKeyStates[i] = saved.rawKeyStates[i] }
            rawStateIndex = saved.rawStateIndex
            droppedKeys = saved.droppedKeys
            tempDisableKey = saved.tempDisableKey
            hasDigitPrefix = saved.hasDigitPrefix
            if vCheckSpelling != 0 { checkSpelling() }
            return buildOutputSnapshot(forKeyCode: keyCode)
        } else {
            navSavedState = nil
            return nil
        }
    }
    
    func countVowelGroups(in keys: [UInt32]) -> Int {
        let vowelKeyCodes: Set<UInt16> = [KEY_A, KEY_E, KEY_I, KEY_O, KEY_U, KEY_Y]
        var groups = 0
        var inVowel = false
        for k in keys {
            let base = UInt16(k & CHAR_MASK)
            if vowelKeyCodes.contains(base) {
                if !inVowel { groups += 1; inVowel = true }
            } else {
                inVowel = false
            }
        }
        return groups
    }
    
    func checkRestoreIfWrongSpelling(handleCode: UInt8) -> Bool {
        return evaluateWordBreakRestore(breakKeyCode: KEY_SPACE, handleCode: handleCode)
    }
    
    func evaluateWordBreakRestore(breakKeyCode: UInt16, handleCode: UInt8) -> Bool {
        guard index > 0 && stateIndex > 0 else { return false }
        let dict = VietnameseDictionary.shared
        
        let fullKeys = Array(rawKeyStates[0..<Int(rawStateIndex)])
        var fullChars: [Character] = []
        for k in fullKeys {
            let c = keyCodeToCharacter(k)
            if let sc = UnicodeScalar(c), c != 0 { fullChars.append(Character(sc)) }
        }
        let fullRawStr = String(fullChars)
        let fullRawLower = fullRawStr.lowercased()
        
        let stdRawKeys = Array(keyStates[0..<Int(stateIndex)])
        var stdChars: [Character] = []
        for k in stdRawKeys {
            let c = keyCodeToCharacter(k)
            if let sc = UnicodeScalar(c), c != 0 { stdChars.append(Character(sc)) }
        }
        let stdRawStr = String(stdChars)
        let stdRawLower = stdRawStr.lowercased()
        
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
        
        // Vietnamese Đ-acronyms ("VĐV", "BĐS", "HĐND") must never be restored
        let vowelKeySet: Set<UInt16> = [KEY_A, KEY_E, KEY_I, KEY_O, KEY_U, KEY_Y]
        let hasStrokeD = (0..<Int(index)).contains { CHR($0) == KEY_D && typingWord[$0].hasCircumflexOrStroke }
        let hasNoVowel = !(0..<Int(index)).contains { vowelKeySet.contains(CHR($0)) }
        let isVietnameseDAcronym = hasStrokeD && hasNoVowel && capitalCount >= 2
        if isVietnameseDAcronym {
            consecutiveEnglishWordCount = 0
            previousWords.removeAll()
            return false
        }
        
        // Single-backspace undo lock (REQ-020)
        if let locked = undoneRawWord {
            if locked == fullRawLower || locked == stdRawLower {
                if breakKeyCode == KEY_SPACE { undoneRawWord = nil }
                return false
            }
            undoneRawWord = nil
        }
        
        let rawCapitalCount = fullKeys.filter { ($0 & CAPS_MASK) != 0 }.count
        let singleToneLower = String(fullRawLower.dropLast())
        let isTrailingDoubledToneEscape: Bool = {
            guard fullKeys.count >= 3 else { return false }
            let lastKey = UInt16(fullKeys[fullKeys.count - 1] & CHAR_MASK)
            let prevKey = UInt16(fullKeys[fullKeys.count - 2] & CHAR_MASK)
            return lastKey == prevKey && isMarkKey(lastKey) && !dict.isEnglishWord(fullRawLower) && dict.isEnglishWord(singleToneLower)
        }()
        
        if isTrailingDoubledToneEscape && composedLower == singleToneLower {
            if breakKeyCode == KEY_SPACE {
                previousWords.append(PreviousWordEntry(rawString: composed, composedString: composed, rawKeys: Array(fullKeys.dropLast()), composedWord: Array(typingWord[0..<Int(index)]), wasRestoredToEnglish: true))
                if previousWords.count > 2 { previousWords.removeFirst(previousWords.count - 2) }
                consecutiveEnglishWordCount += 1
            }
            return false
        }
        
        // -------------------------------------------------------------
        // Intelligence & Ecosystem Enhancements (REQ-024, REQ-025, REQ-026)
        // -------------------------------------------------------------
        let priority = effectiveLanguagePriority()
        let shouldCapitalizeSentence = sentenceEndedWithPunctuation && AutoWordingEngine.shared.isEnabled && AutoWordingEngine.shared.grammarRepairEnabled && wordStartOk
        if breakKeyCode == KEY_SPACE {
            sentenceEndedWithPunctuation = false
        }
        
        // 1. Duplicate Word Collapse (REQ-025, e.g. "the the" -> "the")
        if breakKeyCode == KEY_SPACE && !previousWords.isEmpty {
            let prev = previousWords.last!
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
        }
        
        // 2. Bigram Grammar Corrections (REQ-025)
        var replacementWord: String? = nil
        let isPunctOrSpaceWordBreak = (breakKeyCode == KEY_SPACE || breakKeyCode == KEY_COMMA || breakKeyCode == KEY_DOT || breakKeyCode == KEY_SEMICOLON)
        if isPunctOrSpaceWordBreak && !previousWords.isEmpty {
            let prevEntry = previousWords.last!
            let prevWord = prevEntry.composedString
            let cand1 = "\(prevWord.lowercased()) \(fullRawLower)"
            let cand2 = "\(prevWord.lowercased()) \(composedLower)"
            if let matched = dict.englishBigramGrammar[cand1] ?? dict.englishBigramGrammar[cand2] ?? dict.vietnameseBigramGrammar[cand1] ?? dict.vietnameseBigramGrammar[cand2] {
                let parts = matched.split(separator: " ").map(String.init)
                if parts.count == 2 {
                    let newPrev = parts[0]
                    let newCur = parts[1]
                    if newPrev.lowercased() == prevWord.lowercased() {
                        replacementWord = (fullRawStr.first?.isUppercase == true) ? (newCur.prefix(1).uppercased() + newCur.dropFirst()) : newCur
                    } else if breakKeyCode == KEY_SPACE {
                        // Both previous word and current word change (e.g. "a apple" -> "an apple")
                        let prevCap = prevWord.first?.isUppercase == true
                        let finalPrev = prevCap ? (newPrev.prefix(1).uppercased() + newPrev.dropFirst()) : newPrev
                        let curCap = fullRawStr.first?.isUppercase == true
                        let finalCur = curCap ? (newCur.prefix(1).uppercased() + newCur.dropFirst()) : newCur
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
                        previousWords.append(PreviousWordEntry(rawString: finalCur, composedString: finalCur, rawKeys: stringToTargetKeys(finalCur), composedWord: stringToTargetKeys(finalCur), wasRestoredToEnglish: true))
                        if previousWords.count > 2 { previousWords.removeFirst(previousWords.count - 2) }
                        consecutiveEnglishWordCount += 1
                        startNewSessionInternal()
                        tempDisableKey = false
                        return true
                    }
                }
            }
        }
        
        // 3. English Contraction Grammar (REQ-025)
        if replacementWord == nil {
            if let contraction = dict.englishContractionGrammar[fullRawLower] {
                if fullRawLower != "im" || priority == .englishFirst {
                    let isCap = fullRawStr.first?.isUppercase == true
                    replacementWord = isCap ? (contraction.prefix(1).uppercased() + contraction.dropFirst()) : contraction
                }
            }
        }
        
        // 4. Standalone "i" -> "I" (REQ-025, REQ-030)
        if replacementWord == nil && breakKeyCode == KEY_SPACE {
            if fullRawStr == "i" && composed == "i" && (priority == .englishFirst || !hasAnyDiacritic) {
                replacementWord = "I"
            }
        }
        
        // 5. Typo & Transposition Corrections (REQ-024, REQ-026)
        if replacementWord == nil && rawCapitalCount < 2 && !(breakKeyCode == KEY_QUOTE && fullRawLower.hasSuffix("n")) {
            let prevWord = previousWords.last?.composedString
            if priority == .englishFirst {
                if !dict.isValidVietnameseSyllable(composedLower) {
                    if let engTypo = dict.englishTypoCorrections[fullRawLower] {
                        let isCap = fullRawStr.first?.isUppercase == true
                        replacementWord = isCap ? (engTypo.prefix(1).uppercased() + engTypo.dropFirst()) : engTypo
                    } else if let engTrans = dict.findEnglishTranspositionMatch(fullRawLower) {
                        let isCap = fullRawStr.first?.isUppercase == true
                        replacementWord = isCap ? (engTrans.prefix(1).uppercased() + engTrans.dropFirst()) : engTrans
                    }
                }
                if replacementWord == nil, let vnTypo = dict.vietnameseTypoCorrections[composedLower] ?? dict.vietnameseTypoCorrections[fullRawLower] {
                    let isCap = composed.first?.isUppercase == true || fullRawStr.first?.isUppercase == true
                    replacementWord = isCap ? (vnTypo.prefix(1).uppercased() + vnTypo.dropFirst()) : vnTypo
                }
                if replacementWord == nil && !dict.isValidVietnameseSyllable(composedLower) {
                    if let vnSpatial = dict.findVietnameseSpatialMatch(fullRawLower, composedLower: composedLower, previousWord: prevWord) {
                        let isCap = composed.first?.isUppercase == true || fullRawStr.first?.isUppercase == true
                        replacementWord = isCap ? (vnSpatial.prefix(1).uppercased() + vnSpatial.dropFirst()) : vnSpatial
                    }
                }
            } else {
                if let vnTypo = dict.vietnameseTypoCorrections[composedLower] ?? dict.vietnameseTypoCorrections[fullRawLower] {
                    let isCap = composed.first?.isUppercase == true || fullRawStr.first?.isUppercase == true
                    replacementWord = isCap ? (vnTypo.prefix(1).uppercased() + vnTypo.dropFirst()) : vnTypo
                } else if !dict.isValidVietnameseSyllable(composedLower) {
                    if let vnSpatial = dict.findVietnameseSpatialMatch(fullRawLower, composedLower: composedLower, previousWord: prevWord) {
                        let isCap = composed.first?.isUppercase == true || fullRawStr.first?.isUppercase == true
                        replacementWord = isCap ? (vnSpatial.prefix(1).uppercased() + vnSpatial.dropFirst()) : vnSpatial
                    } else if let engTypo = dict.englishTypoCorrections[fullRawLower] {
                        let isCap = fullRawStr.first?.isUppercase == true
                        replacementWord = isCap ? (engTypo.prefix(1).uppercased() + engTypo.dropFirst()) : engTypo
                    } else if let engTrans = dict.findEnglishTranspositionMatch(fullRawLower) {
                        let isCap = fullRawStr.first?.isUppercase == true
                        replacementWord = isCap ? (engTrans.prefix(1).uppercased() + engTrans.dropFirst()) : engTrans
                    }
                }
            }
        }
        
        // 6. Sentence Capitalization (REQ-025)
        if shouldCapitalizeSentence && breakKeyCode == KEY_SPACE {
            if let rw = replacementWord {
                replacementWord = rw.prefix(1).uppercased() + rw.dropFirst()
            } else {
                let wordToCap = ((dict.isEnglishWord(composedLower) && !hasAnyDiacritic) || (priority != .englishFirst && dict.isValidVietnameseSyllable(composedLower))) ? composed : fullRawStr
                if wordToCap.first?.isLowercase == true {
                    replacementWord = wordToCap.prefix(1).uppercased() + wordToCap.dropFirst()
                }
            }
        }
        
        let isTransformed = hasAnyDiacritic || composed != fullRawStr || isTrailingDoubledToneEscape
        var shouldRestore = false
        var targetKeys: [UInt32] = fullKeys
        
        if replacementWord == composed { replacementWord = nil }
        if let rw = replacementWord {
            shouldRestore = true
            targetKeys = stringToTargetKeys(rw)
        } else if dict.isEnglishWord(composedLower) && !hasAnyDiacritic {
            // REQ-027, ADR-027: Composed Word Protection:
            // If the composed word currently on screen is already a valid English word without diacritics,
            // preserve the composed word as-is and MUST NOT restore raw keystrokes containing cancellation keys ("chaoss", "serrvice", "off").
            shouldRestore = false
        } else if isTransformed {
            if isTrailingDoubledToneEscape {
                shouldRestore = true
                targetKeys = Array(fullKeys.dropLast())
            } else if !wordStartOk {
                // Compound token boundary after '.', '_', '/', '@' ("foo.bars", "my_vars") (REQ-023)
                shouldRestore = true
                targetKeys = fullKeys
            } else if !droppedKeys.isEmpty && dict.isEnglishWord(fullRawLower) && !dict.isEnglishWord(composedLower) {
                // 1. Swallowed mid-word Telex undo key ("cheese", "seemed", "needed", "deepseek", "google", "process", "coffee", "address", "terrible") (REQ-015)
                shouldRestore = true
                targetKeys = fullKeys
            } else if dict.englishPriorityWords.contains(fullRawLower) {
                // 2. Standalone English collision priority word ("test", "list", "more", "core", "user", "tree", "free", "see", "too", "add", "boss", "pass", "mix", "fix") (REQ-017)
                shouldRestore = true
                targetKeys = fullKeys
            } else if priority == .englishFirst && dict.isEnglishWord(fullRawLower) {
                // REQ-018, ADR-019: English priority restores any valid English word on word break
                shouldRestore = true
                targetKeys = fullKeys
            } else if dict.isEnglishWord(fullRawLower) && !dict.isValidVietnameseSyllable(composedLower) {
                // 3. Known English word whose composed output is not a valid Vietnamese syllable ("care" -> "cáe", "pure" -> "pủe", "sure" -> "sủe", "true" -> "trúe", "caesar") (REQ-017)
                shouldRestore = true
                targetKeys = fullKeys
            } else if rawCapitalCount >= 2 {
                // 4. Multi-capital acronym or CamelCase brand ("NAS", "SATA", "GoPro") (REQ-016)
                shouldRestore = true
                targetKeys = fullKeys
            } else if breakKeyCode == KEY_QUOTE && fullRawLower.hasSuffix("n") {
                // 5. English contraction before apostrophe ("doesn't", "isn't") (REQ-016)
                shouldRestore = true
                targetKeys = fullKeys
            } else if breakKeyCode == KEY_MINUS && fullRawLower.hasPrefix("w") {
                // 6. Hyphenated w- word ("Wi-Fi") (REQ-016)
                shouldRestore = true
                targetKeys = fullKeys
            } else if hasDigitPrefix && !dict.isValidVietnameseSyllable(composedLower) {
                // 7. Digit-prefix technical/hex token ("0xdeadbeef", "base64") (REQ-023)
                shouldRestore = true
                targetKeys = fullKeys
            } else if tempDisableKey && (hasAnyDiacritic || !droppedKeys.isEmpty) {
                // 8. Standard OpenKey wrong-spelling fallback
                shouldRestore = true
                targetKeys = dict.isEnglishWord(fullRawLower) ? fullKeys : stdRawKeys
            }
        }
        
        let LookbackTriggerSet: Set<String> = ["is", "as", "us", "if", "of", "or", "for", "his", "has", "was"]
        let restoredIsEnglish = shouldRestore && (replacementWord == nil || dict.isEnglishWord(replacementWord!.lowercased()) || replacementWord == "I")
        let currentIsEnglish = restoredIsEnglish || dict.englishPriorityWords.contains(fullRawLower) || (dict.isEnglishWord(fullRawLower) && !dict.isValidVietnameseSyllable(composedLower)) || LookbackTriggerSet.contains(fullRawLower)
        
        // Check 1-2 word context look-back (REQ-018)
        if breakKeyCode == KEY_SPACE && currentIsEnglish && wordStartOk && !previousWords.isEmpty {
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
            if let startIdx = firstRewriteIdx {
                var totalBackspace = Int(index)
                var combinedRawKeys: [UInt32] = []
                for idx in startIdx..<previousWords.count {
                    totalBackspace += previousWords[idx].composedString.utf16.count + 1 // +1 for single space
                    combinedRawKeys.append(contentsOf: previousWords[idx].rawKeys)
                    combinedRawKeys.append(UInt32(KEY_SPACE))
                    previousWords[idx].wasRestoredToEnglish = true
                    previousWords[idx].composedString = previousWords[idx].rawString
                }
                let curKeys = shouldRestore ? targetKeys : fullKeys
                combinedRawKeys.append(contentsOf: curKeys)
                
                if combinedRawKeys.count <= 31 {
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
                    
                    var targetChars: [Character] = []
                    for k in curKeys {
                        if (k & PURE_CHARACTER_MASK) != 0 {
                            if let sc = UnicodeScalar(UInt16(k & 0xFFFF)) { targetChars.append(Character(sc)) }
                        } else {
                            let c = keyCodeToCharacter(k)
                            if let sc = UnicodeScalar(c), c != 0 { targetChars.append(Character(sc)) }
                        }
                    }
                    let restoredStr = String(targetChars)
                    previousWords.append(PreviousWordEntry(rawString: restoredStr, composedString: restoredStr, rawKeys: curKeys, composedWord: curKeys, wasRestoredToEnglish: true))
                    if previousWords.count > 2 { previousWords.removeFirst(previousWords.count - 2) }
                    consecutiveEnglishWordCount += 2
                    if consecutiveEnglishWordCount >= 3 {
                        hookOutput.languageSwitchRequest = 0
                    }
                    return true
                }
            }
        }
        
        if shouldRestore {
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
            
            var targetChars: [Character] = []
            for k in targetKeys {
                if (k & PURE_CHARACTER_MASK) != 0 {
                    if let sc = UnicodeScalar(UInt16(k & 0xFFFF)) { targetChars.append(Character(sc)) }
                } else {
                    let c = keyCodeToCharacter(k)
                    if let sc = UnicodeScalar(c), c != 0 { targetChars.append(Character(sc)) }
                }
            }
            let targetStr = String(targetChars)
            
            // Save single-backspace undo state (REQ-020)
            let breakChar = keyCodeToCharacter(UInt32(breakKeyCode) | (isCaps ? CAPS_MASK : 0))
            let trailingCount = (breakChar != 0) ? 1 : 0
            let origComposed = (replacementWord != nil && dict.vietnameseTypoCorrections[composedLower] == nil && dict.vietnameseBigramGrammar.values.allSatisfy({ !$0.hasSuffix(targetStr.lowercased()) })) ? fullRawStr : composed
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
        } else {
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
            return false
        }
    }
    
    func handleEnglishModeKeyEvent(keyCode: UInt16, capsStatus: UInt8, otherControlKey: Bool) -> OKHookSnapshot {
        lock.lock()
        defer { lock.unlock() }
        
        if otherControlKey { enKeys.removeAll(); wordStartOk = true; return OKHookSnapshot(code: HookCodeState.doNothing) }
        if keyCode == KEY_DELETE { if !enKeys.isEmpty { enKeys.removeLast() }; return OKHookSnapshot(code: HookCodeState.doNothing) }
        
        let isAlphaKey = !isNumberKey(keyCode) && !charKeyCode.contains(keyCode)
        let isBreak = breakCode.contains(keyCode) || keyCode == KEY_SPACE
        
        if !isBreak && isAlphaKey && enKeys.count < maxBuff {
            let caps = (capsStatus == 1) || (capsStatus == 2 && isAlphaKey)
            enKeys.append(UInt32(keyCode) | (caps ? CAPS_MASK : 0))
            return OKHookSnapshot(code: HookCodeState.doNothing)
        }
        
        if isBreak {
            let isCompoundSep = (keyCode == KEY_DOT || (keyCode == KEY_MINUS && capsStatus == 1) || keyCode == KEY_SLASH || (keyCode == KEY_2 && capsStatus == 1))
            let savedEnKeys = enKeys
            let canReplay = wordStartOk && !savedEnKeys.isEmpty
            enKeys.removeAll()
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
            enKeys.removeAll()
        }
        return OKHookSnapshot(code: HookCodeState.doNothing)
    }
}

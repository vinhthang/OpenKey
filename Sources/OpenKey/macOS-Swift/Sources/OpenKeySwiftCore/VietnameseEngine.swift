//
//  VietnameseEngine.swift
//  OpenKeySwiftCore
//
//  Converted to 100% Pure Swift 6 by Antigravity from the original C++ OpenKey engine:
//  Created by Mai Vũ Tuyên on 1/18/19.
//  Copyright © 2019 Mai Vũ Tuyên. All rights reserved.
//  Licensed under GNU General Public License v3.0.
//

import Foundation

// MARK: - Engine Word Context (REQ-008, ADR-007)

public struct OKWordContext: Sendable, Equatable {
    public let composedWord: String
    public let rawKeystrokes: String
    public let charCount: Int
    public let spaceCount: Int
    public let isWrongSpelling: Bool
    public let isBreakKey: Bool
    
    public init(composedWord: String = "", rawKeystrokes: String = "", charCount: Int = 0, spaceCount: Int = 0, isWrongSpelling: Bool = false, isBreakKey: Bool = false) {
        self.composedWord = composedWord; self.rawKeystrokes = rawKeystrokes; self.charCount = charCount; self.spaceCount = spaceCount
        self.isWrongSpelling = isWrongSpelling; self.isBreakKey = isBreakKey
    }
}

// MARK: - Internal Engine State Machine

final class VietnameseEngineState: @unchecked Sendable {
    static let shared = VietnameseEngineState()
    
    let lock = NSLock()
    
    // Configuration variables
    var vLanguage: Int = 1
    var vInputType: Int = 0 // 0: Telex, 1: VNI
    var vCheckSpelling: Int = 1
    var vUseModernOrthography: Int = 1
    var vRestoreIfWrongSpelling: Int = 1
    var vFixRecommendBrowser: Int = 1
    var vUseSmartSwitchKey: Int = 1
    var vQuickTelex: Int = 0
    
    // Optional Hook for Phonotactic Syllable Repair (ADR-007)
    var phonotacticRepairHook: ((inout [UInt32], UInt8, UInt8, UInt8, UInt8, Bool) -> Bool)?
    
    // Break & special character key sets
    let charKeyCode: [UInt16] = [KEY_BACKQUOTE, KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9, KEY_0, KEY_MINUS, KEY_EQUALS, KEY_LEFT_BRACKET, KEY_RIGHT_BRACKET, KEY_BACK_SLASH, KEY_SEMICOLON, KEY_QUOTE, KEY_COMMA, KEY_DOT, KEY_SLASH]
    let breakCode: [UInt16] = [
        KEY_ESC, KEY_TAB, KEY_ENTER, KEY_RETURN, KEY_LEFT, KEY_RIGHT, KEY_DOWN, KEY_UP,
        KEY_HOME, KEY_PAGE_UP, KEY_FORWARD_DELETE, KEY_END, KEY_PAGE_DOWN,
        KEY_F1, KEY_F2, KEY_F3, KEY_F4, KEY_F5, KEY_F6, KEY_F7, KEY_F8, KEY_F9, KEY_F10,
        KEY_F11, KEY_F12, KEY_F13, KEY_F14, KEY_F15, KEY_F16, KEY_F17, KEY_F18, KEY_F19, KEY_F20,
        KEY_COMMA, KEY_DOT, KEY_SLASH, KEY_SEMICOLON, KEY_QUOTE, KEY_BACK_SLASH, KEY_MINUS, KEY_EQUALS, KEY_BACKQUOTE
    ]
    let processingChar: [[UInt16]] = [
        [KEY_S, KEY_F, KEY_R, KEY_X, KEY_J, KEY_A, KEY_O, KEY_E, KEY_W, KEY_D, KEY_Z],
        [KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_6, KEY_7, KEY_8, KEY_9, KEY_0]
    ]
    
    // Syllable buffer
    let maxBuff = 32
    var typingWord = [UInt32](repeating: 0, count: 32)
    var index: UInt8 = 0
    var longWordHelper: [UInt32] = []
    var typingStates: [[UInt32]] = []
    var typingStatesData: [UInt32] = []
    
    // Keystroke state buffer for restoring
    var keyStates = [UInt32](repeating: 0, count: 32)
    var stateIndex: UInt8 = 0
    
    // Full raw keystrokes including swallowed Telex undo keys (REQ-015, ADR-014)
    var rawKeyStates = [UInt32](repeating: 0, count: 64)
    var rawStateIndex: UInt8 = 0
    var droppedKeys: [(key: UInt32, pos: Int)] = []
    
    // Multi-word context look-back, undo, and context guards (REQ-018, REQ-019, REQ-020, REQ-023)
    var previousWords: [PreviousWordEntry] = []
    var sentenceEndedWithPunctuation: Bool = false
    var consecutiveEnglishWordCount: Int = 0
    var autoRestoreUndoState: AutoRestoreUndoSnapshot? = nil
    var undoneRawWord: String? = nil
    var hasDigitPrefix: Bool = false
    var wordStartOk: Bool = true
    var lastSpaceUptime: TimeInterval = 0
    struct CompoundSegmentRecord {
        var screenLength: Int
        var rawKeys: [UInt32]
        var separatorKey: UInt32
        var wasTransformed: Bool
    }
    var compoundSegments: [CompoundSegmentRecord] = []
    
    // Transient flags
    var tempDisableKey: Bool = false
    var isCorrect: Bool = false
    var isChanged: Bool = false
    var vowelCount: UInt8 = 0
    var vowelStartIndex: UInt8 = 0
    var vowelEndIndex: UInt8 = 0
    var vowelWillSetMark: UInt8 = 0
    var isRestoredW: Bool = false
    var keyForAEO: UInt16 = 0
    var isCheckedGrammar: Bool = false
    var isCaps: Bool = false
    var spaceCount: Int = 0
    var isCharKeyCode: Bool = false
    var specialChar: [UInt32] = []
    var useSpellCheckingBefore: Int = 1
    var willTempOffEngine: Bool = false
    
    var spellingOK: Bool = false
    var spellingFlag: Bool = false
    var spellingVowelOK: Bool = false
    var spellingEndIndex: UInt8 = 0
    
    // Hook output state
    struct HookOutput {
        var code: UInt8 = 0
        var backspaceCount: UInt8 = 0
        var newCharCount: UInt8 = 0
        var extCode: UInt8 = 0
        var charData = [UInt32](repeating: 0, count: 32)
        var languageSwitchRequest: Int8 = -1
    }
    var hookOutput = HookOutput()
    
    // MARK: - Key Predicates
    
    func isKeyZ(_ key: UInt16) -> Bool { processingChar[vInputType][10] == key }
    func isKeyD(_ key: UInt16) -> Bool { processingChar[vInputType][9] == key }
    func isKeyW(_ key: UInt16) -> Bool {
        (vInputType != 1) ? (processingChar[vInputType][8] == key) : (processingChar[vInputType][8] == key || processingChar[vInputType][7] == key)
    }
    func isKeyDouble(_ key: UInt16) -> Bool {
        (vInputType != 1) ? (processingChar[vInputType][5] == key || processingChar[vInputType][6] == key || processingChar[vInputType][7] == key) : (processingChar[vInputType][6] == key)
    }
    func isKeyS(_ key: UInt16) -> Bool { processingChar[vInputType][0] == key }
    func isKeyF(_ key: UInt16) -> Bool { processingChar[vInputType][1] == key }
    func isKeyR(_ key: UInt16) -> Bool { processingChar[vInputType][2] == key }
    func isKeyX(_ key: UInt16) -> Bool { processingChar[vInputType][3] == key }
    func isKeyJ(_ key: UInt16) -> Bool { processingChar[vInputType][4] == key }
    
    func isMarkKey(_ keyCode: UInt16) -> Bool {
        (vInputType != 1) ? [KEY_S, KEY_F, KEY_R, KEY_J, KEY_X].contains(keyCode) : [KEY_1, KEY_2, KEY_3, KEY_5, KEY_4].contains(keyCode)
    }
    func isBracketKey(_ key: UInt16) -> Bool { key == KEY_LEFT_BRACKET || key == KEY_RIGHT_BRACKET }
    func isSpecialKey(_ keyCode: UInt16) -> Bool {
        (vInputType == 0) ? [KEY_W, KEY_E, KEY_R, KEY_O, KEY_LEFT_BRACKET, KEY_RIGHT_BRACKET, KEY_A, KEY_S, KEY_D, KEY_F, KEY_J, KEY_Z, KEY_X].contains(keyCode) : isNumberKey(keyCode)
    }
    
    @inline(__always)
    func CHR(_ idx: Int) -> UInt16 {
        guard idx >= 0 && idx < Int(index) && idx < maxBuff else { return KEY_EMPTY }
        return UInt16(typingWord[idx] & CHAR_MASK)
    }
    
    @inline(__always)
    func GET(_ data: UInt32) -> UInt32 { getCharacterCode(data) }
    
    func isWordBreak(isMouse: Bool, data: UInt16) -> Bool { isMouse || breakCode.contains(data) }
    
    func setKeyData(idx: Int, keyCode: UInt16, caps: Bool) {
        typingWord[idx] = UInt32(keyCode) | (caps ? CAPS_MASK : 0)
    }
    
    // MARK: - Lifecycle
    
    func clearBuffersInternal() {
        index = 0
        stateIndex = 0
        rawStateIndex = 0
        droppedKeys.removeAll()
        hasDigitPrefix = false
        tempDisableKey = false
        longWordHelper.removeAll()
        for i in 0..<maxBuff {
            typingWord[i] = UInt32(KEY_EMPTY)
            keyStates[i] = UInt32(KEY_EMPTY)
        }
        for i in 0..<rawKeyStates.count {
            rawKeyStates[i] = UInt32(KEY_EMPTY)
        }
    }
    
    func initEngine() {
        lock.lock()
        defer { lock.unlock() }
        clearBuffersInternal()
        isCorrect = false; isChanged = false; vowelCount = 0; vowelStartIndex = 0; vowelEndIndex = 0; vowelWillSetMark = 0
        isRestoredW = false; keyForAEO = 0; isCheckedGrammar = false; isCaps = false; spaceCount = 0; isCharKeyCode = false
        specialChar.removeAll(); useSpellCheckingBefore = vCheckSpelling; willTempOffEngine = false
        previousWords.removeAll(); consecutiveEnglishWordCount = 0
        autoRestoreUndoState = nil; undoneRawWord = nil
        hasDigitPrefix = false; wordStartOk = true
        sentenceEndedWithPunctuation = false
        lastSpaceUptime = 0
        compoundSegments.removeAll()
    }
    
    func getWordContext(forKeyCode keyCode: UInt16? = nil) -> OKWordContext {
        lock.lock()
        defer { lock.unlock() }
        return getWordContextUnlocked(forKeyCode: keyCode)
    }
    
    func getWordContextUnlocked(forKeyCode keyCode: UInt16? = nil) -> OKWordContext {
        var wordChars: [Character] = []
        for i in 0..<Int(index) {
            let code = GET(typingWord[i])
            let utf16Val: UInt16 = ((code & CHAR_CODE_MASK) != 0 || (code & PURE_CHARACTER_MASK) != 0) ? UInt16(code & 0xFFFF) : keyCodeToCharacter(code)
            if let scalar = UnicodeScalar(utf16Val), utf16Val != 0 { wordChars.append(Character(scalar)) }
        }
        var rawChars: [Character] = []
        for i in 0..<Int(stateIndex) {
            let rawVal = keyCodeToCharacter(keyStates[i])
            if let scalar = UnicodeScalar(rawVal), rawVal != 0 { rawChars.append(Character(scalar)) }
        }
        let isBreak = keyCode.map { isWordBreak(isMouse: false, data: $0) || $0 == KEY_SPACE || $0 == KEY_RETURN || $0 == KEY_ENTER } ?? false
        return OKWordContext(
            composedWord: String(wordChars),
            rawKeystrokes: String(rawChars),
            charCount: Int(index),
            spaceCount: spaceCount,
            isWrongSpelling: tempDisableKey,
            isBreakKey: isBreak
        )
    }
    
    func commitExternalExpansion() {
        lock.lock()
        defer { lock.unlock() }
        clearBuffersInternal()
        spaceCount = 0
        specialChar.removeAll()
        typingStates.removeAll()
        typingStatesData.removeAll()
    }

    func lastPreviousWord() -> String? {
        lock.lock()
        defer { lock.unlock() }
        return previousWords.last?.composedString
    }
    
    @discardableResult
    func resetSession() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let wasDirty = index > 0 || stateIndex > 0 || rawStateIndex > 0 || !specialChar.isEmpty || !typingStates.isEmpty || spaceCount > 0 || !previousWords.isEmpty || consecutiveEnglishWordCount > 0 || autoRestoreUndoState != nil || undoneRawWord != nil || hasDigitPrefix || !wordStartOk || sentenceEndedWithPunctuation || willTempOffEngine
        clearBuffersInternal()
        specialChar.removeAll()
        typingStates.removeAll()
        typingStatesData.removeAll()
        spaceCount = 0
        lastSpaceUptime = 0
        willTempOffEngine = false
        previousWords.removeAll()
        consecutiveEnglishWordCount = 0
        autoRestoreUndoState = nil
        undoneRawWord = nil
        hasDigitPrefix = false
        wordStartOk = true
        sentenceEndedWithPunctuation = false
        compoundSegments.removeAll()
        return wasDirty
    }
    
    func startNewSessionInternal() {
        clearBuffersInternal()
    }
    
    func getComposedWordInternal() -> String {
        let chars = (0..<Int(index)).compactMap { i -> Character? in
            let code = GET(typingWord[i])
            let val = ((code & CHAR_CODE_MASK) != 0 || (code & PURE_CHARACTER_MASK) != 0) ? UInt16(code & 0xFFFF) : keyCodeToCharacter(code)
            return (val != 0) ? UnicodeScalar(val).map(Character.init) : nil
        }
        return String(chars)
    }

    func getComposedWord() -> String {
        lock.lock()
        defer { lock.unlock() }
        return getComposedWordInternal()
    }
    
    func insertKey(keyCode: UInt16, caps: Bool, isCheckSpellingFlag: Bool = true) {
        if Int(index) >= maxBuff {
            longWordHelper.append(typingWord[0])
            for iii in 0..<(maxBuff - 1) { typingWord[iii] = typingWord[iii + 1] }
            setKeyData(idx: Int(index) - 1, keyCode: keyCode, caps: caps)
        } else {
            setKeyData(idx: Int(index), keyCode: keyCode, caps: caps)
            index += 1
        }
        if vCheckSpelling != 0 && isCheckSpellingFlag { checkSpelling() }
        if keyCode == KEY_D && Int(index) - 2 >= 0 && isConsonant(CHR(Int(index) - 2)) { tempDisableKey = false }
    }
    
    func insertState(keyCode: UInt16, caps: Bool) {
        let entry = UInt32(keyCode) | (caps ? CAPS_MASK : 0)
        if Int(stateIndex) >= maxBuff {
            for iii in 0..<(maxBuff - 1) { keyStates[iii] = keyStates[iii + 1] }
            keyStates[Int(stateIndex) - 1] = entry
        } else {
            keyStates[Int(stateIndex)] = entry
            stateIndex += 1
        }
        if Int(rawStateIndex) >= rawKeyStates.count {
            for iii in 0..<(rawKeyStates.count - 1) { rawKeyStates[iii] = rawKeyStates[iii + 1] }
            rawKeyStates[Int(rawStateIndex) - 1] = entry
        } else {
            rawKeyStates[Int(rawStateIndex)] = entry
            rawStateIndex += 1
        }
    }
    
    func saveWord() {
        guard index > 0 else { return }
        if !longWordHelper.isEmpty {
            typingStatesData.removeAll()
            for (i, val) in longWordHelper.enumerated() {
                if i != 0 && i % maxBuff == 0 {
                    typingStates.append(typingStatesData)
                    typingStatesData.removeAll()
                }
                typingStatesData.append(val)
            }
            typingStates.append(typingStatesData)
            longWordHelper.removeAll()
        }
        typingStates.append(Array(typingWord[0..<Int(index)]))
    }
    
    func saveWord(keyCode: UInt32, count: Int) {
        typingStates.append(Array(repeating: keyCode, count: count))
    }
    
    func saveSpecialChar() {
        typingStates.append(specialChar)
        specialChar.removeAll()
    }
    
    func restoreLastTypingState() {
        guard !typingStates.isEmpty else {
            previousWords.removeAll()
            return
        }
        typingStatesData = typingStates.removeLast()
        guard !typingStatesData.isEmpty else { return }
        if typingStatesData[0] == UInt32(KEY_SPACE) {
            spaceCount = typingStatesData.count; index = 0
        } else if charKeyCode.contains(UInt16(typingStatesData[0] & CHAR_MASK)) {
            index = 0; specialChar = typingStatesData; checkSpelling()
        } else {
            for i in 0..<typingStatesData.count {
                typingWord[i] = typingStatesData[i]
                keyStates[i] = typingStatesData[i]
                rawKeyStates[i] = typingStatesData[i]
            }
            index = UInt8(typingStatesData.count); stateIndex = index; rawStateIndex = index
            droppedKeys.removeAll()
            for i in Int(index)..<maxBuff {
                typingWord[i] = UInt32(KEY_EMPTY); keyStates[i] = UInt32(KEY_EMPTY)
            }
            for i in Int(index)..<rawKeyStates.count {
                rawKeyStates[i] = UInt32(KEY_EMPTY)
            }
            if vCheckSpelling != 0 { checkSpelling() }
        }
    }
    
    func syncConfig(
        language: Int? = nil, inputType: Int? = nil, checkSpelling: Int? = nil,
        useModernOrthography: Int? = nil, restoreIfWrongSpelling: Int? = nil,
        fixRecommendBrowser: Int? = nil, useSmartSwitchKey: Int? = nil,
        quickTelex: Int? = nil
    ) {
        lock.lock()
        defer { lock.unlock() }
        if let language { vLanguage = language }
        if let inputType { vInputType = inputType }
        if let checkSpelling { vCheckSpelling = checkSpelling; useSpellCheckingBefore = checkSpelling }
        if let useModernOrthography { vUseModernOrthography = useModernOrthography }
        if let restoreIfWrongSpelling { vRestoreIfWrongSpelling = restoreIfWrongSpelling }
        if let fixRecommendBrowser { vFixRecommendBrowser = fixRecommendBrowser }
        if let useSmartSwitchKey { vUseSmartSwitchKey = useSmartSwitchKey }
        if let quickTelex { vQuickTelex = quickTelex }
    }
}

// MARK: - Public C-ABI Bridge Functions for VietnameseEngine

public func OKEngineInit() {
    _ = VietnameseDictionary.shared
    VietnameseEngineState.shared.initEngine()
    VietnameseEngineState.shared.phonotacticRepairHook = { (word, idx, vsi, vei, vc, isMark) in
        AutoWordingEngine.shared.repairPhonotacticCluster(typingWord: &word, index: idx, vowelStartIndex: vsi, vowelEndIndex: vei, vowelCount: vc, isInsertingMark: isMark)
    }
}

public func OKEngineSyncConfig(
    _ language: Int32, _ inputType: Int32, _ checkSpelling: Int32,
    _ useModernOrthography: Int32, _ restoreIfWrongSpelling: Int32,
    _ fixRecommendBrowser: Int32, _ useSmartSwitchKey: Int32,
    _ autoWordingEnabled: Int32 = 0,
    _ grammarRepairEnabled: Int32 = 0,
    _ shorthandExpansionEnabled: Int32 = 0,
    _ candidateSuggestionsEnabled: Int32 = 0,
    _ doubleSpacePeriodEnabled: Int32 = 0,
    _ quickTelexEnabled: Int32 = 0
) {
    VietnameseEngineState.shared.syncConfig(
        language: Int(language), inputType: Int(inputType), checkSpelling: Int(checkSpelling),
        useModernOrthography: Int(useModernOrthography), restoreIfWrongSpelling: Int(restoreIfWrongSpelling),
        fixRecommendBrowser: Int(fixRecommendBrowser), useSmartSwitchKey: Int(useSmartSwitchKey),
        quickTelex: Int(quickTelexEnabled)
    )
    AutoWordingEngine.shared.syncConfig(
        isEnabled: autoWordingEnabled != 0,
        grammarRepair: grammarRepairEnabled != 0,
        shorthandExpansion: shorthandExpansionEnabled != 0,
        candidateSuggestions: candidateSuggestionsEnabled != 0,
        doubleSpacePeriod: doubleSpacePeriodEnabled != 0
    )
}

public func OKEngineGetWordContext(_ keyCode: UInt16? = nil) -> OKWordContext {
    VietnameseEngineState.shared.getWordContext(forKeyCode: keyCode)
}

public func OKEngineCommitExternalExpansion() {
    VietnameseEngineState.shared.commitExternalExpansion()
}

public func OKEngineHandleKeyEvent(
    _ keyCode: UInt16, _ capsStatus: UInt8, _ otherControlKey: Bool
) -> OKHookSnapshot {
    if !AutoWordingEngine.shared.isEnabled {
        let snapshot = VietnameseEngineState.shared.handleKeyEvent(keyCode: keyCode, capsStatus: capsStatus, otherControlKey: otherControlKey)
        if OpenKeyLogger.shared.isEnabled {
            let postContext = VietnameseEngineState.shared.getWordContext(forKeyCode: keyCode)
            OpenKeyLogger.shared.log(.engine, "OKEngineHandleKeyEvent: key=\(keyCode), caps=\(capsStatus) -> code=\(snapshot.code), bs=\(snapshot.backspaceCount), new=\(snapshot.newCharCount), word='\(postContext.composedWord)'")
        }
        return snapshot
    }
    
    let engine = VietnameseEngineState.shared
    let preContext = engine.getWordContext(forKeyCode: keyCode)
    
    if let interceptResult = AutoWordingEngine.shared.interceptBeforeKeyEvent(keyCode: keyCode, preContext: preContext) {
        engine.commitExternalExpansion()
        return interceptResult
    }
    
    let snapshot = engine.handleKeyEvent(keyCode: keyCode, capsStatus: capsStatus, otherControlKey: otherControlKey)
    let postContext = engine.getWordContext(forKeyCode: keyCode)
    
    OpenKeyLogger.shared.log(.engine, "OKEngineHandleKeyEvent: key=\(keyCode), caps=\(capsStatus) -> code=\(snapshot.code), bs=\(snapshot.backspaceCount), new=\(snapshot.newCharCount), word='\(postContext.composedWord)'")
    
    AutoWordingEngine.shared.didProcessKeyEvent(keyCode: keyCode, snapshot: snapshot, preContext: preContext, postContext: postContext)
    return snapshot
}

public func OKEngineResetSession() {
    let wasDirty = VietnameseEngineState.shared.resetSession()
    let hadCandidates = !AutoWordingEngine.shared.activeCandidates.isEmpty
    AutoWordingEngine.shared.handleSessionReset()
    if wasDirty || hadCandidates {
        OpenKeyLogger.shared.log(.engine, "OKEngineResetSession")
    }
}

public func OKEngineKeyCodeToChar(_ keyCodeWithCaps: UInt32) -> UInt16 {
    keyCodeToCharacter(keyCodeWithCaps)
}

public func OKEngineHandleEnglishModeKeyEvent(_ keyCode: UInt16, _ capsStatus: UInt8, _ otherControlKey: Bool) -> OKHookSnapshot {
    VietnameseEngineState.shared.handleEnglishModeKeyEvent(keyCode: keyCode, capsStatus: capsStatus, otherControlKey: otherControlKey)
}

public enum VietnameseEngine {
    public static func lastPreviousWord() -> String? {
        VietnameseEngineState.shared.lastPreviousWord()
    }
}

// MARK: - Event Dispatcher Extension (REQ-008, REQ-009, REQ-015..020, REQ-023)

extension VietnameseEngineState {
    
    func handleKeyEvent(keyCode: UInt16, capsStatus: UInt8, otherControlKey: Bool) -> OKHookSnapshot {
        lock.lock()
        defer { lock.unlock() }
        
        hookOutput.code = HookCodeState.doNothing
        hookOutput.backspaceCount = 0
        hookOutput.newCharCount = 0
        hookOutput.extCode = 0
        hookOutput.charData[0] = 0
        hookOutput.languageSwitchRequest = -1
        
        // Single-backspace undo of auto-restore (REQ-020)
        if keyCode == KEY_DELETE && capsStatus == 0 && !otherControlKey {
            if let snapshot = handleSingleBackspaceUndo() {
                return snapshot
            }
        }
        if keyCode != KEY_DELETE {
            autoRestoreUndoState = nil
        }
        
        let isAlphaKey = !isNumberKey(keyCode) && !charKeyCode.contains(keyCode) && keyCode != KEY_SPACE
        isCaps = (capsStatus == 1) || (capsStatus == 2 && isAlphaKey)
        
        let isWordBreakCondition = (isNumberKey(keyCode) && capsStatus == 1) ||
            otherControlKey ||
            isWordBreak(isMouse: false, data: keyCode) ||
            (index == 0 && isNumberKey(keyCode))
        
        if isWordBreakCondition {
            handleWordBreakOrControlKey(keyCode: keyCode, capsStatus: capsStatus)
        } else if keyCode == KEY_SPACE {
            handleSpaceKey()
        } else if keyCode == KEY_DELETE {
            handleDeleteKey()
        } else {
            handleCharacterKey(keyCode: keyCode)
        }
        
        return buildOutputSnapshot(forKeyCode: keyCode)
    }
    
    func handleWordBreakOrControlKey(keyCode: UInt16, capsStatus: UInt8) {
        sentenceEndedWithPunctuation = false
        hookOutput.code = HookCodeState.doNothing
        hookOutput.backspaceCount = 0
        hookOutput.newCharCount = 0
        hookOutput.extCode = 1 // Word break
        
        // D33: Digit at start of word (REQ-023)
        if index == 0 && isNumberKey(keyCode) && capsStatus == 0 {
            if spaceCount > 0 {
                saveWord(keyCode: UInt32(KEY_SPACE), count: spaceCount)
                spaceCount = 0
            }
            specialChar.append(UInt32(keyCode))
            hookOutput.extCode = 3
            startNewSessionInternal()
            hasDigitPrefix = true
            vCheckSpelling = useSpellCheckingBefore
            willTempOffEngine = false
            return
        }
        
        let isCompoundSeparator = (keyCode == KEY_DOT && capsStatus != 1) ||
            (keyCode == KEY_MINUS) ||
            (keyCode == KEY_EQUALS && capsStatus != 1) ||
            (keyCode == KEY_SLASH && capsStatus != 1) ||
            (keyCode == KEY_BACK_SLASH && capsStatus != 1) ||
            (keyCode == KEY_7 && capsStatus == 1) ||
            (keyCode == KEY_2 && capsStatus == 1) ||
            (keyCode == KEY_SEMICOLON && capsStatus == 1)
        
        if vRestoreIfWrongSpelling != 0 && isWordBreak(isMouse: false, data: keyCode) {
            if !tempDisableKey && vCheckSpelling != 0 {
                checkSpelling(forceCheckVowel: true)
            }
            if !evaluateWordBreakRestore(breakKeyCode: keyCode, handleCode: HookCodeState.restoreAndStartNewSession) {
                hookOutput.code = HookCodeState.doNothing
            }
        }
        
        isCharKeyCode = charKeyCode.contains(keyCode)
        if !isCharKeyCode {
            specialChar.removeAll()
            typingStates.removeAll()
            previousWords.removeAll()
            compoundSegments.removeAll()
            wordStartOk = true
        } else {
            let preSaveScreenLen = Int(index)
            let preSaveRawKeys = Array(rawKeyStates[0..<Int(rawStateIndex)])
            let preSaveTransformed = (0..<preSaveScreenLen).contains { typingWord[$0].hasAnyDiacritic }
            if spaceCount > 0 {
                saveWord(keyCode: UInt32(KEY_SPACE), count: spaceCount)
                spaceCount = 0
            } else {
                saveWord()
            }
            let sepEntry = UInt32(keyCode) | (isCaps ? CAPS_MASK : 0)
            specialChar.append(sepEntry)
            hookOutput.extCode = 3
            if isCompoundSeparator {
                if preSaveScreenLen > 0 {
                    compoundSegments.append(CompoundSegmentRecord(
                        screenLength: preSaveScreenLen,
                        rawKeys: preSaveRawKeys,
                        separatorKey: sepEntry,
                        wasTransformed: preSaveTransformed
                    ))
                }
                wordStartOk = false
                previousWords.removeAll()
            } else {
                compoundSegments.removeAll()
                wordStartOk = true
            }
        }
        
        if hookOutput.code == HookCodeState.doNothing {
            startNewSessionInternal()
            vCheckSpelling = useSpellCheckingBefore
            willTempOffEngine = false
        }
    }
    
    func handleSpaceKey() {
        let now = ProcessInfo.processInfo.systemUptime
        if spaceCount == 1 && handleDoubleSpacePeriod() {
            lastSpaceUptime = now
            return
        }
        lastSpaceUptime = now
        
        if spaceCount == 0 {
            if !tempDisableKey && vCheckSpelling != 0 {
                checkSpelling(forceCheckVowel: true)
            }
            if vRestoreIfWrongSpelling != 0 {
                if !evaluateWordBreakRestore(breakKeyCode: KEY_SPACE, handleCode: HookCodeState.restore) {
                    hookOutput.code = HookCodeState.doNothing
                }
                spaceCount += 1
            } else {
                hookOutput.code = HookCodeState.doNothing
                spaceCount += 1
            }
        } else {
            hookOutput.code = HookCodeState.doNothing
            spaceCount += 1
        }
        
        if spaceCount == 1 {
            if !specialChar.isEmpty {
                if let lastSpecial = specialChar.last, isSentenceEndingPunctuation(lastSpecial) {
                    sentenceEndedWithPunctuation = true
                }
                saveSpecialChar()
            } else {
                saveWord()
            }
        } else if spaceCount > 1 {
            previousWords.removeAll()
        }
        wordStartOk = true
        hasDigitPrefix = false
        compoundSegments.removeAll()
        vCheckSpelling = useSpellCheckingBefore
        willTempOffEngine = false
    }
    
    func handleDeleteKey() {
        hookOutput.code = HookCodeState.doNothing
        hookOutput.extCode = 2 // Delete
        if !specialChar.isEmpty {
            specialChar.removeLast()
            if specialChar.isEmpty {
                restoreLastTypingState()
            }
        } else if spaceCount > 0 {
            spaceCount -= 1
            if spaceCount == 0 {
                lastSpaceUptime = 0
                if !previousWords.isEmpty { previousWords.removeLast() }
                restoreLastTypingState()
            }
        } else {
            if stateIndex > 0 {
                stateIndex -= 1
            }
            if rawStateIndex > 0 {
                rawStateIndex -= 1
            }
            if index > 0 {
                index -= 1
                typingWord[Int(index)] = UInt32(KEY_EMPTY)
                let currentIdx = Int(index)
                droppedKeys.removeAll { $0.pos >= currentIdx }
                if !longWordHelper.isEmpty {
                    for i in stride(from: maxBuff - 1, through: 1, by: -1) {
                        typingWord[i] = typingWord[i - 1]
                    }
                    typingWord[0] = longWordHelper.removeLast()
                    index += 1
                }
                if vCheckSpelling != 0 {
                    checkSpelling()
                }
                syncKeyStatesFromTypingWord()
            }
            
            hookOutput.backspaceCount = 0
            hookOutput.newCharCount = 0
            hookOutput.extCode = 2
            if index == 0 {
                stateIndex = 0
                rawStateIndex = 0
                droppedKeys.removeAll()
                longWordHelper.removeAll()
                startNewSessionInternal()
                specialChar.removeAll()
                if typingStates.isEmpty { previousWords.removeAll() }
                restoreLastTypingState()
            } else {
                checkGrammar(deltaBackSpace: 1)
            }
        }
    }

    private func syncKeyStatesFromTypingWord() {
        var rebuilt: [UInt32] = []
        let count = Int(index)
        for i in 0..<count {
            let w = typingWord[i]
            let base = UInt16(w & CHAR_MASK)
            let capsFlag: UInt32 = w.isCaps ? CAPS_MASK : 0
            if w.isStandaloneW {
                if base == KEY_U {
                    rebuilt.append(UInt32(vInputType == 0 ? KEY_W : KEY_RIGHT_BRACKET) | capsFlag)
                } else if base == KEY_O {
                    rebuilt.append(UInt32(vInputType == 0 ? KEY_LEFT_BRACKET : KEY_LEFT_BRACKET) | capsFlag)
                } else {
                    rebuilt.append(UInt32(base) | capsFlag)
                }
                continue
            }
            rebuilt.append(UInt32(base) | capsFlag)
            if w.hasCircumflexOrStroke {
                if base == KEY_D {
                    rebuilt.append(UInt32(vInputType == 0 ? KEY_D : KEY_9))
                } else {
                    rebuilt.append(UInt32(vInputType == 0 ? base : KEY_6))
                }
            }
            if w.hasHornOrBreve {
                let isUOFirst = (base == KEY_U && i + 1 < count && CHR(i + 1) == KEY_O && typingWord[i + 1].hasHornOrBreve)
                if !isUOFirst {
                    rebuilt.append(UInt32(vInputType == 0 ? KEY_W : ((base == KEY_A) ? KEY_8 : KEY_7)))
                }
            }
            let mark = w & MARK_MASK
            if mark != 0 {
                let markKey: UInt16 = {
                    if vInputType == 0 {
                        if mark == MARK1_MASK { return KEY_S }
                        if mark == MARK2_MASK { return KEY_F }
                        if mark == MARK3_MASK { return KEY_R }
                        if mark == MARK4_MASK { return KEY_X }
                        return KEY_J
                    } else {
                        if mark == MARK1_MASK { return KEY_1 }
                        if mark == MARK2_MASK { return KEY_2 }
                        if mark == MARK3_MASK { return KEY_3 }
                        if mark == MARK4_MASK { return KEY_4 }
                        return KEY_5
                    }
                }()
                rebuilt.append(UInt32(markKey))
            }
        }
        droppedKeys.removeAll()
        let stateCount = min(rebuilt.count, maxBuff)
        stateIndex = UInt8(stateCount)
        for i in 0..<maxBuff {
            keyStates[i] = (i < stateCount) ? rebuilt[i] : UInt32(KEY_EMPTY)
        }
        let rawCount = min(rebuilt.count, rawKeyStates.count)
        rawStateIndex = UInt8(rawCount)
        for i in 0..<rawKeyStates.count {
            rawKeyStates[i] = (i < rawCount) ? rebuilt[i] : UInt32(KEY_EMPTY)
        }
    }
    
    public static let doubleConsonantEnglishStems: Set<String> = [
        "err", "corr", "curr", "sorr", "morr", "tomorr", "borr", "carr", "marr",
        "hurr", "worr", "arr", "narr", "mirr", "terr", "horr", "occurr", "recurr",
        "off", "eff", "diff", "buff", "suff", "coff", "traff", "aff", "stiff",
        "cliff", "staff", "stuff", "mess", "iss", "tiss", "sess", "less", "poss",
        "pass", "ass", "press", "express", "impress", "compress", "address",
        "process", "success", "access", "assess", "discuss", "miss", "loss",
        "cross", "boss", "class", "glass", "grass", "mass", "dress", "stress", "guess"
    ]
    
    func restoreWordFromRawKeys(oldScreenLength: Int) {
        let targetLen = min(Int(rawStateIndex), maxBuff)
        var diffIdx = 0
        while diffIdx < oldScreenLength && diffIdx < targetLen {
            if GET(typingWord[diffIdx]) != GET(rawKeyStates[diffIdx]) {
                break
            }
            diffIdx += 1
        }
        for i in 0..<targetLen {
            typingWord[i] = rawKeyStates[i]
            keyStates[i] = rawKeyStates[i]
        }
        for i in targetLen..<maxBuff {
            typingWord[i] = UInt32(KEY_EMPTY)
            keyStates[i] = UInt32(KEY_EMPTY)
        }
        index = UInt8(targetLen)
        stateIndex = UInt8(targetLen)
        droppedKeys.removeAll()
        tempDisableKey = true
        if vCheckSpelling != 0 {
            checkSpelling(forceCheckVowel: true)
        }
        let bsCount = max(0, oldScreenLength - diffIdx)
        let newCount = max(0, targetLen - diffIdx)
        hookOutput.code = HookCodeState.willProcess
        hookOutput.backspaceCount = UInt8(bsCount)
        hookOutput.newCharCount = UInt8(newCount)
        hookOutput.extCode = 3
        for i in diffIdx..<targetLen {
            hookOutput.charData[targetLen - 1 - i] = GET(typingWord[i])
        }
    }
    
    func checkLiveMidWordAutoEscape(keyCode: UInt16) -> Bool {
        guard vInputType == 0 else { return false }
        
        // 1. Double-Consonant rr/ff/ss + Vowel Live Mid-Word Restoration ("correct", "error", "errors", "sorry", "current", "office", "coffee", "message", "issue")
        if tempDisableKey && !droppedKeys.isEmpty && Int(rawStateIndex) >= 4 {
            if [KEY_A, KEY_E, KEY_I, KEY_O, KEY_U, KEY_Y].contains(keyCode) {
                let rawBeforeLen = Int(rawStateIndex) - 1
                if rawBeforeLen >= 2 {
                    let c1 = UInt16(rawKeyStates[rawBeforeLen - 1] & CHAR_MASK)
                    let c2 = UInt16(rawKeyStates[rawBeforeLen - 2] & CHAR_MASK)
                    if c1 == c2 && [KEY_R, KEY_F, KEY_S, KEY_J, KEY_X].contains(c1) {
                        var stemChars: [Character] = []
                        for i in 0..<rawBeforeLen {
                            let keyVal = rawKeyStates[i]
                            let charCode = keyCodeToCharacter(keyVal)
                            if charCode != 0, let scalar = UnicodeScalar(charCode) {
                                stemChars.append(Character(scalar))
                            }
                        }
                        let stemLower = String(stemChars).lowercased()
                        if Self.doubleConsonantEnglishStems.contains(stemLower) {
                            restoreWordFromRawKeys(oldScreenLength: Int(index))
                            return true
                        }
                    }
                }
            }
        }
        
        // 2. Compound Interleaved Tone + Circumflex Telex Escape (these + s/e -> "these")
        if !tempDisableKey && index >= 2 && Int(rawStateIndex) - 1 > Int(index) {
            findAndCalculateVowel()
            if vowelCount > 0 {
                let vsi = Int(vowelStartIndex)
                let vei = Int(vowelEndIndex)
                for vi in vsi...vei {
                    let tw = typingWord[vi]
                    if (tw & TONE_MASK) != 0 && (tw & MARK_MASK) != 0 {
                        var markKey: UInt16? = nil
                        if (tw & MARK1_MASK) != 0 { markKey = KEY_S }
                        else if (tw & MARK2_MASK) != 0 { markKey = KEY_F }
                        else if (tw & MARK3_MASK) != 0 { markKey = KEY_R }
                        else if (tw & MARK4_MASK) != 0 { markKey = KEY_X }
                        else if (tw & MARK5_MASK) != 0 { markKey = KEY_J }
                        
                        if let mk = markKey {
                            let vKey = CHR(vi)
                            let isRepeatingKey = (keyCode == vKey || keyCode == mk)
                            let rsi = Int(rawStateIndex)
                            if isRepeatingKey && rsi >= 3 {
                                let prevKey1 = UInt16(rawKeyStates[rsi - 3] & CHAR_MASK)
                                let prevKey2 = UInt16(rawKeyStates[rsi - 2] & CHAR_MASK)
                                if prevKey1 == mk && prevKey2 == vKey {
                                    if rawStateIndex > 0 { rawStateIndex -= 1 }
                                    if stateIndex > 0 { stateIndex -= 1 }
                                    restoreWordFromRawKeys(oldScreenLength: Int(index))
                                    return true
                                }
                            }
                        }
                    }
                }
            }
        }
        
        // 3. Post-Tone KEY_E Mid-Word Auto-Restore ("more", "core", "store", "care", "share", "fire", "sure", "case", "nose", "use", "house", "life")
        if !tempDisableKey && keyCode == KEY_E && index >= 1 && Int(rawStateIndex) >= 3 {
            findAndCalculateVowel()
            if vowelCount > 0 && Int(vowelEndIndex) == Int(index) - 1 {
                let vRange = Int(vowelStartIndex)...Int(vowelEndIndex)
                let noEY = !vRange.contains { CHR($0) == KEY_E || CHR($0) == KEY_Y }
                let noCircumflexOrHorn = !vRange.contains { (typingWord[$0] & (TONE_MASK | TONEW_MASK)) != 0 }
                let hasMark = vRange.contains { (typingWord[$0] & MARK_MASK) != 0 }
                if noEY && noCircumflexOrHorn && hasMark && Int(rawStateIndex) >= 2 {
                    let lastRawBeforeE = UInt16(rawKeyStates[Int(rawStateIndex) - 2] & CHAR_MASK)
                    if [KEY_F, KEY_S, KEY_R, KEY_X, KEY_J].contains(lastRawBeforeE) {
                        restoreWordFromRawKeys(oldScreenLength: Int(index))
                        return true
                    }
                }
            }
        }
        
        // 4. Invalid Post-Vowel Coda Consonant Mid-Word Auto-Restore ("needed", "good", "book", "feel", "work", "word", "part", "start", "sort", "soft", "left", "text", "next")
        if !tempDisableKey && index >= 2 {
            findAndCalculateVowel()
            if vowelCount > 0 && Int(vowelEndIndex) == Int(index) - 1 {
                let vRange = Int(vowelStartIndex)...Int(vowelEndIndex)
                let hasVowelMod = vRange.contains { (typingWord[$0] & (TONE_MASK | TONEW_MASK | MARK_MASK)) != 0 }
                if hasVowelMod {
                    let isImpossibleCoda = [KEY_B, KEY_K, KEY_L, KEY_Q, KEY_V].contains(keyCode) || (keyCode == KEY_D && CHR(0) != KEY_D)
                    let hasNonEnteringMark = vRange.contains { (typingWord[$0] & (MARK2_MASK | MARK3_MASK | MARK4_MASK)) != 0 }
                    let isIncompatibleStopCoda = [KEY_C, KEY_P, KEY_T].contains(keyCode) && hasNonEnteringMark
                    if isImpossibleCoda || isIncompatibleStopCoda {
                        restoreWordFromRawKeys(oldScreenLength: Int(index))
                        return true
                    }
                }
            }
        }
        
        return false
    }
    
    func handleCharacterKey(keyCode: UInt16) {
        if willTempOffEngine {
            hookOutput.code = HookCodeState.doNothing
            hookOutput.extCode = 3
            return
        }
        
        if spaceCount > 0 {
            hookOutput.backspaceCount = 0
            hookOutput.newCharCount = 0
            hookOutput.extCode = 0
            startNewSessionInternal()
            saveWord(keyCode: UInt32(KEY_SPACE), count: spaceCount)
            spaceCount = 0
        } else if !specialChar.isEmpty {
            let preserveDigitPrefix = hasDigitPrefix
            saveSpecialChar()
            hasDigitPrefix = preserveDigitPrefix
        }
        
        // REQ-027, ADR-027: Escape Keystroke Consumption
        // Consume redundant trailing 'i' only on an accented diphthong ending in off-glide 'i'
        // (must check before insertState so keyStates/rawKeyStates remain synchronized with screen).
        if vInputType == 0 && index >= 2 && keyCode == KEY_I && CHR(Int(index) - 1) == KEY_I && !isConsonant(CHR(Int(index) - 2)) {
            let hasDiacritic = (0..<Int(index)).contains { typingWord[$0].hasAnyDiacritic }
            if hasDiacritic && VietnameseDictionary.shared.isValidVietnameseSyllable(getComposedWordInternal().lowercased()) {
                hookOutput.code = HookCodeState.willProcess
                hookOutput.backspaceCount = 0
                hookOutput.newCharCount = 0
                hookOutput.extCode = 3
                return
            }
        }
        
        insertState(keyCode: keyCode, caps: isCaps)
        
        // Quick Telex: cc->ch, gg->gi, kk->kh, nn->ng, pp->ph, qq->qu, tt->tr
        if vQuickTelex != 0 && vInputType == 0 && !tempDisableKey && index == 1 && CHR(0) == keyCode {
            let quickSecond: UInt16? = {
                switch keyCode {
                case KEY_C, KEY_K, KEY_P: return KEY_H
                case KEY_G: return KEY_I
                case KEY_N: return KEY_G
                case KEY_Q: return KEY_U
                case KEY_T: return KEY_R
                default: return nil
                }
            }()
            if let second = quickSecond {
                insertKey(keyCode: second, caps: isCaps)
                if Int(stateIndex) > 0 { keyStates[Int(stateIndex) - 1] = UInt32(second) | (isCaps ? CAPS_MASK : 0) }
                hookOutput.code = HookCodeState.willProcess
                hookOutput.backspaceCount = 0
                hookOutput.newCharCount = 1
                hookOutput.extCode = 3
                hookOutput.charData[0] = GET(typingWord[Int(index) - 1])
                return
            }
        }
        
        // D33: Check for hex prefix 0x or technical digit-inside-word (Telex mode only)
        if hasDigitPrefix && index == 0 && keyCode == KEY_X {
            tempDisableKey = true
        } else if vInputType == 0 && index > 0 && isNumberKey(keyCode) {
            tempDisableKey = true
        }
        
        // REQ-030, ADR-030: Immediate word-initial standalone 'w' ('ư') auto-revert on non-Vietnamese 2nd letters
        let nonInitialUFollowers: Set<UInt16> = [KEY_E, KEY_I, KEY_H, KEY_Y, KEY_L, KEY_B, KEY_D, KEY_G, KEY_K, KEY_Q, KEY_V]
        if vInputType == 0 && index == 1 && CHR(0) == KEY_U && typingWord[0].isStandaloneW && nonInitialUFollowers.contains(keyCode) {
            let wCaps = typingWord[0].isCaps
            typingWord[0] = UInt32(KEY_W) | (wCaps ? CAPS_MASK : 0)
            keyStates[0] = typingWord[0]
            rawKeyStates[0] = typingWord[0]
            tempDisableKey = true
            insertKey(keyCode: keyCode, caps: isCaps, isCheckSpellingFlag: false)
            hookOutput.code = HookCodeState.willProcess
            hookOutput.backspaceCount = 1
            hookOutput.newCharCount = 2
            hookOutput.extCode = 3
            hookOutput.charData[1] = GET(typingWord[0])
            hookOutput.charData[0] = GET(typingWord[1])
            return
        }
        
        // REQ-021, ADR-022: Live mid-word phonotactic auto-escape
        if checkLiveMidWordAutoEscape(keyCode: keyCode) {
            return
        }
        
        // Re-upgrade restored "wow" -> "ươ" + coda when continued with a Vietnamese coda (e.g. "wowns" -> "ướn")
        if vInputType == 0 && isRestoredW && index == 3 && CHR(0) == KEY_W && CHR(1) == KEY_O && CHR(2) == KEY_W &&
           [KEY_N, KEY_M, KEY_C, KEY_P, KEY_T].contains(keyCode) {
            let w0Caps = typingWord[0].isCaps
            let oCaps = typingWord[1].isCaps
            typingWord[0] = UInt32(KEY_U) | TONEW_MASK | STANDALONE_MASK | (w0Caps ? CAPS_MASK : 0)
            typingWord[1] = UInt32(KEY_O) | TONEW_MASK | (oCaps ? CAPS_MASK : 0)
            typingWord[2] = UInt32(keyCode) | (isCaps ? CAPS_MASK : 0)
            isRestoredW = false
            tempDisableKey = false
            if vCheckSpelling != 0 { checkSpelling() }
            hookOutput.code = HookCodeState.willProcess
            hookOutput.backspaceCount = 3
            hookOutput.newCharCount = 3
            hookOutput.extCode = 3
            hookOutput.charData[2] = GET(typingWord[0])
            hookOutput.charData[1] = GET(typingWord[1])
            hookOutput.charData[0] = GET(typingWord[2])
            return
        }
        
        if !isSpecialKey(keyCode) || tempDisableKey {
            hookOutput.code = HookCodeState.doNothing
            hookOutput.backspaceCount = 0
            hookOutput.newCharCount = 0
            hookOutput.extCode = 3
            insertKey(keyCode: keyCode, caps: isCaps)
        } else {
            hookOutput.code = HookCodeState.doNothing
            hookOutput.extCode = 3
            handleMainKey(data: keyCode, caps: isCaps)
        }
        
        if !isKeyD(keyCode) {
            if hookOutput.code == HookCodeState.doNothing || (hookOutput.extCode == 4 && hookOutput.backspaceCount == 0 && hookOutput.newCharCount == 1) {
                checkGrammar(deltaBackSpace: -1)
            } else {
                checkGrammar(deltaBackSpace: 0)
            }
        }
        
        if hookOutput.code == HookCodeState.restore {
            let swallowedEntry = UInt32(keyCode) | (isCaps ? CAPS_MASK : 0)
            droppedKeys.append((key: swallowedEntry, pos: Int(index)))
            insertKey(keyCode: keyCode, caps: isCaps)
            if stateIndex > 0 {
                stateIndex -= 1
            }
        }
        
        if isBracketKey(keyCode) && (hookOutput.code == HookCodeState.doNothing || isBracketKey(UInt16(hookOutput.charData[0] & CHAR_MASK))) {
            let deduction = (hookOutput.code == HookCodeState.willProcess) ? Int(hookOutput.backspaceCount) : 0
            if Int(index) - deduction > 0 {
                index -= 1
                saveWord()
            }
            index = 0
            tempDisableKey = false
            stateIndex = 0
            rawStateIndex = 0
            droppedKeys.removeAll()
            hookOutput.extCode = 3
            specialChar.append(UInt32(keyCode) | (isCaps ? CAPS_MASK : 0))
        }
    }
    
    func buildOutputSnapshot(forKeyCode keyCode: UInt16) -> OKHookSnapshot {
        if hookOutput.code == HookCodeState.doNothing {
            return OKHookSnapshot(
                code: HookCodeState.doNothing,
                backspaceCount: 0,
                newCharCount: 0,
                extCode: hookOutput.extCode,
                shouldSendControlKey: false,
                utf16Chars: [],
                languageSwitchRequest: hookOutput.languageSwitchRequest
            )
        }
        
        var chars: [UInt16] = []
        if hookOutput.newCharCount > 0 {
            for k in stride(from: Int(hookOutput.newCharCount) - 1, through: 0, by: -1) {
                let tempChar = hookOutput.charData[k]
                if (tempChar & PURE_CHARACTER_MASK) != 0 {
                    chars.append(UInt16(tempChar & 0xFFFF))
                } else if (tempChar & CHAR_CODE_MASK) == 0 {
                    chars.append(keyCodeToCharacter(tempChar))
                } else {
                    chars.append(UInt16(tempChar & 0xFFFF))
                }
            }
        }
        
        var shouldSendControl = false
        if hookOutput.code == HookCodeState.restore || hookOutput.code == HookCodeState.restoreAndStartNewSession {
            let baseChar = keyCodeToCharacter(UInt32(keyCode))
            if baseChar != 0 {
                let c = keyCodeToCharacter(UInt32(keyCode) | (isCaps ? CAPS_MASK : 0))
                chars.append(c != 0 ? c : baseChar)
            } else {
                shouldSendControl = true
            }
            if hookOutput.code == HookCodeState.restoreAndStartNewSession {
                startNewSessionInternal()
            }
        }
        
        return OKHookSnapshot(
            code: hookOutput.code,
            backspaceCount: hookOutput.backspaceCount,
            newCharCount: UInt8(chars.count),
            extCode: hookOutput.extCode,
            shouldSendControlKey: shouldSendControl,
            utf16Chars: chars,
            languageSwitchRequest: hookOutput.languageSwitchRequest
        )
    }
}

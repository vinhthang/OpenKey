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
    
    // Optional Hook for Phonotactic Syllable Repair (ADR-007)
    var phonotacticRepairHook: ((inout [UInt32], UInt8, UInt8, UInt8, UInt8, Bool) -> Bool)?
    
    // Break & special character key sets
    let charKeyCode: [UInt16] = [KEY_BACKQUOTE, KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9, KEY_0, KEY_MINUS, KEY_EQUALS, KEY_LEFT_BRACKET, KEY_RIGHT_BRACKET, KEY_BACK_SLASH, KEY_SEMICOLON, KEY_QUOTE, KEY_COMMA, KEY_DOT, KEY_SLASH]
    let breakCode: [UInt16] = [KEY_ESC, KEY_TAB, KEY_ENTER, KEY_RETURN, KEY_LEFT, KEY_RIGHT, KEY_DOWN, KEY_UP, KEY_COMMA, KEY_DOT, KEY_SLASH, KEY_SEMICOLON, KEY_QUOTE, KEY_BACK_SLASH, KEY_MINUS, KEY_EQUALS, KEY_BACKQUOTE, KEY_TAB]
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
        tempDisableKey = false
        longWordHelper.removeAll()
        for i in 0..<maxBuff {
            typingWord[i] = UInt32(KEY_EMPTY)
            keyStates[i] = UInt32(KEY_EMPTY)
        }
    }
    
    func initEngine() {
        lock.lock()
        defer { lock.unlock() }
        clearBuffersInternal()
        isCorrect = false; isChanged = false; vowelCount = 0; vowelStartIndex = 0; vowelEndIndex = 0; vowelWillSetMark = 0
        isRestoredW = false; keyForAEO = 0; isCheckedGrammar = false; isCaps = false; spaceCount = 0; isCharKeyCode = false
        specialChar.removeAll(); useSpellCheckingBefore = vCheckSpelling; willTempOffEngine = false
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
    
    func resetSession() {
        lock.lock()
        defer { lock.unlock() }
        clearBuffersInternal()
        specialChar.removeAll()
        typingStates.removeAll()
        typingStatesData.removeAll()
        spaceCount = 0
        willTempOffEngine = false
    }
    
    func startNewSessionInternal() {
        clearBuffersInternal()
    }
    
    func getComposedWord() -> String {
        lock.lock()
        defer { lock.unlock() }
        let chars = (0..<Int(index)).compactMap { i -> Character? in
            let code = GET(typingWord[i])
            let val = ((code & CHAR_CODE_MASK) != 0 || (code & PURE_CHARACTER_MASK) != 0) ? UInt16(code & 0xFFFF) : keyCodeToCharacter(code)
            return (val != 0) ? UnicodeScalar(val).map(Character.init) : nil
        }
        return String(chars)
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
        if Int(stateIndex) >= maxBuff {
            for iii in 0..<(maxBuff - 1) { keyStates[iii] = keyStates[iii + 1] }
            keyStates[Int(stateIndex) - 1] = UInt32(keyCode) | (caps ? CAPS_MASK : 0)
        } else {
            keyStates[Int(stateIndex)] = UInt32(keyCode) | (caps ? CAPS_MASK : 0)
            stateIndex += 1
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
        guard !typingStates.isEmpty else { return }
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
            }
            index = UInt8(typingStatesData.count); stateIndex = index
            for i in Int(index)..<maxBuff {
                typingWord[i] = UInt32(KEY_EMPTY); keyStates[i] = UInt32(KEY_EMPTY)
            }
            if vCheckSpelling != 0 { checkSpelling() }
        }
    }
    
    func syncConfig(
        language: Int? = nil, inputType: Int? = nil, checkSpelling: Int? = nil,
        useModernOrthography: Int? = nil, restoreIfWrongSpelling: Int? = nil,
        fixRecommendBrowser: Int? = nil, useSmartSwitchKey: Int? = nil
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
    }
}

// MARK: - Public C-ABI Bridge Functions for VietnameseEngine

public func OKEngineInit() {
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
    _ candidateSuggestionsEnabled: Int32 = 0
) {
    VietnameseEngineState.shared.syncConfig(
        language: Int(language), inputType: Int(inputType), checkSpelling: Int(checkSpelling),
        useModernOrthography: Int(useModernOrthography), restoreIfWrongSpelling: Int(restoreIfWrongSpelling),
        fixRecommendBrowser: Int(fixRecommendBrowser), useSmartSwitchKey: Int(useSmartSwitchKey)
    )
    AutoWordingEngine.shared.syncConfig(
        isEnabled: autoWordingEnabled != 0,
        grammarRepair: grammarRepairEnabled != 0,
        shorthandExpansion: shorthandExpansionEnabled != 0,
        candidateSuggestions: candidateSuggestionsEnabled != 0
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
        return VietnameseEngineState.shared.handleKeyEvent(keyCode: keyCode, capsStatus: capsStatus, otherControlKey: otherControlKey)
    }
    
    let engine = VietnameseEngineState.shared
    let preContext = engine.getWordContext(forKeyCode: keyCode)
    
    if let interceptResult = AutoWordingEngine.shared.interceptBeforeKeyEvent(keyCode: keyCode, preContext: preContext) {
        engine.commitExternalExpansion()
        return interceptResult
    }
    
    let snapshot = engine.handleKeyEvent(keyCode: keyCode, capsStatus: capsStatus, otherControlKey: otherControlKey)
    let postContext = engine.getWordContext(forKeyCode: keyCode)
    
    AutoWordingEngine.shared.didProcessKeyEvent(keyCode: keyCode, snapshot: snapshot, preContext: preContext, postContext: postContext)
    return snapshot
}

public func OKEngineResetSession() {
    VietnameseEngineState.shared.resetSession()
    AutoWordingEngine.shared.handleSessionReset()
}

public func OKEngineKeyCodeToChar(_ keyCodeWithCaps: UInt32) -> UInt16 {
    keyCodeToCharacter(keyCodeWithCaps)
}

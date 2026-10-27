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

// MARK: - Internal Engine State Machine

private final class VietnameseEngineState: @unchecked Sendable {
    static let shared = VietnameseEngineState()
    
    private let lock = NSLock()
    
    // Configuration variables
    var vLanguage: Int = 1
    var vInputType: Int = 0 // 0: Telex, 1: VNI
    var vCheckSpelling: Int = 1
    var vUseModernOrthography: Int = 1
    var vRestoreIfWrongSpelling: Int = 1
    var vFixRecommendBrowser: Int = 1
    var vUseSmartSwitchKey: Int = 1
    var vAutoWordingEnabled: Int = 0
    var vGrammarRepairEnabled: Int = 0
    var vShorthandExpansionEnabled: Int = 0
    var vCandidateSuggestionsEnabled: Int = 0
    
    // Break & special character key sets
    private let charKeyCode: [UInt16] = [
        KEY_BACKQUOTE, KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9, KEY_0,
        KEY_MINUS, KEY_EQUALS, KEY_LEFT_BRACKET, KEY_RIGHT_BRACKET, KEY_BACK_SLASH,
        KEY_SEMICOLON, KEY_QUOTE, KEY_COMMA, KEY_DOT, KEY_SLASH
    ]
    
    private let breakCode: [UInt16] = [
        KEY_ESC, KEY_TAB, KEY_ENTER, KEY_RETURN, KEY_LEFT, KEY_RIGHT, KEY_DOWN, KEY_UP,
        KEY_COMMA, KEY_DOT, KEY_SLASH, KEY_SEMICOLON, KEY_QUOTE, KEY_BACK_SLASH,
        KEY_MINUS, KEY_EQUALS, KEY_BACKQUOTE, KEY_TAB
    ]
    
    private let processingChar: [[UInt16]] = [
        [KEY_S, KEY_F, KEY_R, KEY_X, KEY_J, KEY_A, KEY_O, KEY_E, KEY_W, KEY_D, KEY_Z], // Telex
        [KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_6, KEY_7, KEY_8, KEY_9, KEY_0]  // VNI
    ]
    
    // Syllable buffer
    private let maxBuff = 32
    private var typingWord = [UInt32](repeating: 0, count: 32)
    private var index: UInt8 = 0
    private var longWordHelper: [UInt32] = []
    private var typingStates: [[UInt32]] = []
    private var typingStatesData: [UInt32] = []
    
    // Keystroke state buffer for restoring
    private var keyStates = [UInt32](repeating: 0, count: 32)
    private var stateIndex: UInt8 = 0
    
    // Transient flags
    private var tempDisableKey: Bool = false
    private var isCorrect: Bool = false
    private var isChanged: Bool = false
    private var vowelCount: UInt8 = 0
    private var vowelStartIndex: UInt8 = 0
    private var vowelEndIndex: UInt8 = 0
    private var vowelWillSetMark: UInt8 = 0
    private var isRestoredW: Bool = false
    private var keyForAEO: UInt16 = 0
    private var isCheckedGrammar: Bool = false
    private var isCaps: Bool = false
    private var spaceCount: Int = 0
    private var isCharKeyCode: Bool = false
    private var specialChar: [UInt32] = []
    private var useSpellCheckingBefore: Int = 1
    private var willTempOffEngine: Bool = false
    
    private var spellingOK: Bool = false
    private var spellingFlag: Bool = false
    private var spellingVowelOK: Bool = false
    private var spellingEndIndex: UInt8 = 0
    
    // Hook output state
    private struct HookOutput {
        var code: UInt8 = 0
        var backspaceCount: UInt8 = 0
        var newCharCount: UInt8 = 0
        var extCode: UInt8 = 0
        var charData = [UInt32](repeating: 0, count: 32)
    }
    private var hookOutput = HookOutput()
    
    // SmartSwitchKey dictionary
    private var smartSwitchData: [String: Int8] = [:]
    private var smartSwitchCacheKey: String = ""
    private var smartSwitchCacheData: Int8 = 0
    
    // MARK: - Key Predicates
    
    private func isKeyZ(_ key: UInt16) -> Bool {
        processingChar[vInputType][10] == key
    }
    
    private func isKeyD(_ key: UInt16) -> Bool {
        processingChar[vInputType][9] == key
    }
    
    private func isKeyW(_ key: UInt16) -> Bool {
        if vInputType != 1 {
            return processingChar[vInputType][8] == key
        } else {
            return processingChar[vInputType][8] == key || processingChar[vInputType][7] == key
        }
    }
    
    private func isKeyDouble(_ key: UInt16) -> Bool {
        if vInputType != 1 {
            return processingChar[vInputType][5] == key || processingChar[vInputType][6] == key || processingChar[vInputType][7] == key
        } else {
            return processingChar[vInputType][6] == key
        }
    }
    
    private func isKeyS(_ key: UInt16) -> Bool { processingChar[vInputType][0] == key }
    private func isKeyF(_ key: UInt16) -> Bool { processingChar[vInputType][1] == key }
    private func isKeyR(_ key: UInt16) -> Bool { processingChar[vInputType][2] == key }
    private func isKeyX(_ key: UInt16) -> Bool { processingChar[vInputType][3] == key }
    private func isKeyJ(_ key: UInt16) -> Bool { processingChar[vInputType][4] == key }
    
    private func isMarkKey(_ keyCode: UInt16) -> Bool {
        if vInputType != 1 {
            return keyCode == KEY_S || keyCode == KEY_F || keyCode == KEY_R || keyCode == KEY_J || keyCode == KEY_X
        } else {
            return keyCode == KEY_1 || keyCode == KEY_2 || keyCode == KEY_3 || keyCode == KEY_5 || keyCode == KEY_4
        }
    }
    
    private func isBracketKey(_ key: UInt16) -> Bool {
        key == KEY_LEFT_BRACKET || key == KEY_RIGHT_BRACKET
    }
    
    private func isSpecialKey(_ keyCode: UInt16) -> Bool {
        if vInputType == 0 { // Telex
            return keyCode == KEY_W || keyCode == KEY_E || keyCode == KEY_R || keyCode == KEY_O ||
                   keyCode == KEY_LEFT_BRACKET || keyCode == KEY_RIGHT_BRACKET || keyCode == KEY_A ||
                   keyCode == KEY_S || keyCode == KEY_D || keyCode == KEY_F || keyCode == KEY_J ||
                   keyCode == KEY_Z || keyCode == KEY_X
        } else if vInputType == 1 { // VNI
            return isNumberKey(keyCode)
        }
        return false
    }
    
    @inline(__always)
    private func CHR(_ idx: Int) -> UInt16 {
        guard idx >= 0 && idx < Int(index) && idx < maxBuff else { return KEY_EMPTY }
        return UInt16(typingWord[idx] & CHAR_MASK)
    }
    
    @inline(__always)
    private func GET(_ data: UInt32) -> UInt32 {
        getCharacterCode(data)
    }
    
    // MARK: - Lifecycle
    
    func initEngine() {
        lock.lock()
        defer { lock.unlock() }
        index = 0
        stateIndex = 0
        useSpellCheckingBefore = vCheckSpelling
        typingStatesData.removeAll()
        typingStates.removeAll()
        specialChar.removeAll()
        spaceCount = 0
        willTempOffEngine = false
        hookOutput.code = HookCodeState.doNothing
        hookOutput.backspaceCount = 0
        hookOutput.newCharCount = 0
        hookOutput.extCode = 0
        longWordHelper.removeAll()
        for i in 0..<maxBuff {
            typingWord[i] = UInt32(KEY_EMPTY)
            keyStates[i] = UInt32(KEY_EMPTY)
        }
    }
    
    func resetSession() {
        lock.lock()
        defer { lock.unlock() }
        startNewSessionInternal()
        typingStates.removeAll()
        typingStatesData.removeAll()
        specialChar.removeAll()
        spaceCount = 0
        willTempOffEngine = false
        hookOutput.code = HookCodeState.doNothing
        hookOutput.backspaceCount = 0
        hookOutput.newCharCount = 0
        hookOutput.extCode = 0
        if vAutoWordingEnabled != 0 && vCandidateSuggestionsEnabled != 0 {
            AutoWordingEngine.shared.clearCandidates()
        }
    }
    
    private func startNewSessionInternal() {
        index = 0
        tempDisableKey = false
        stateIndex = 0
        longWordHelper.removeAll()
        for i in 0..<maxBuff {
            typingWord[i] = UInt32(KEY_EMPTY)
            keyStates[i] = UInt32(KEY_EMPTY)
        }
    }
    
    func getComposedWord() -> String {
        guard index > 0 && spaceCount == 0 else { return "" }
        var result = ""
        for i in 0..<Int(index) {
            let code = GET(typingWord[i])
            let charCode: UInt16
            if (code & PURE_CHARACTER_MASK) != 0 || (code & CHAR_CODE_MASK) != 0 {
                charCode = UInt16(code & 0xFFFF)
            } else {
                charCode = keyCodeToCharacter(code)
            }
            if charCode != 0, let scalar = UnicodeScalar(charCode) {
                result.append(Character(scalar))
            }
        }
        return result
    }
    
    // MARK: - Character Code Resolution
    
    private func getCharacterCode(_ data: UInt32) -> UInt32 {
        let capsElem: Int = ((data & CAPS_MASK) != 0) ? 0 : 1
        var key = data & CHAR_MASK
        
        if (data & MARK_MASK) != 0 {
            var markElem = -2
            switch data & MARK_MASK {
            case MARK1_MASK: markElem = 0
            case MARK2_MASK: markElem = 2
            case MARK3_MASK: markElem = 4
            case MARK4_MASK: markElem = 6
            case MARK5_MASK: markElem = 8
            default: break
            }
            markElem += capsElem
            
            switch UInt16(key) {
            case KEY_A, KEY_O, KEY_U, KEY_E:
                if (data & TONE_MASK) == 0 && (data & TONEW_MASK) == 0 {
                    markElem += 4
                }
            default: break
            }
            
            if (data & TONE_MASK) != 0 {
                key |= TONE_MASK
            } else if (data & TONEW_MASK) != 0 {
                key |= TONEW_MASK
            }
            
            guard let table = _codeTable[key], markElem >= 0 && markElem < table.count else {
                return data
            }
            return UInt32(table[markElem]) | CHAR_CODE_MASK
        } else {
            guard let table = _codeTable[key] else {
                return data
            }
            if (data & TONE_MASK) != 0 {
                guard capsElem < table.count else { return data }
                return UInt32(table[capsElem]) | CHAR_CODE_MASK
            } else if (data & TONEW_MASK) != 0 {
                guard (capsElem + 2) < table.count else { return data }
                return UInt32(table[capsElem + 2]) | CHAR_CODE_MASK
            } else {
                return data
            }
        }
    }
    
    // MARK: - Word Break Check
    
    private func isWordBreak(isMouse: Bool, data: UInt16) -> Bool {
        if isMouse { return true }
        return breakCode.contains(data)
    }
    
    private func setKeyData(idx: Int, keyCode: UInt16, caps: Bool) {
        guard idx >= 0 && idx < maxBuff else { return }
        typingWord[idx] = UInt32(keyCode) | (caps ? CAPS_MASK : 0)
    }
    
    // MARK: - Spelling Check
    
    private func checkSpelling(forceCheckVowel: Bool = false) {
        spellingOK = false
        spellingVowelOK = true
        spellingEndIndex = index
        
        if index > 0 && CHR(Int(index) - 1) == KEY_RIGHT_BRACKET {
            spellingEndIndex = index - 1
        }
        
        let endIdx = Int(spellingEndIndex)
        if endIdx > 0 {
            var j = 0
            if isConsonant(CHR(0)) {
                for i in 0..<_consonantTable.count {
                    spellingFlag = false
                    if endIdx < _consonantTable[i].count {
                        spellingFlag = true
                    }
                    var matchCount = 0
                    for jElem in 0..<_consonantTable[i].count {
                        matchCount = jElem + 1
                        if endIdx > jElem && _consonantTable[i][jElem] != CHR(jElem) {
                            spellingFlag = true
                            break
                        }
                    }
                    if spellingFlag { continue }
                    j = matchCount
                    break
                }
            }
            
            if j == endIdx { // "d" case
                spellingOK = true
            }
            
            var k = j
            vowelStartIndex = UInt8(k)
            
            if CHR(Int(vowelStartIndex)) == KEY_U && k > 0 && k < endIdx - 1 && CHR(Int(vowelStartIndex) - 1) == KEY_Q {
                k += 1
                j = k
                vowelStartIndex = UInt8(k)
            } else if index >= 2 && CHR(0) == KEY_G && CHR(1) == KEY_I && isConsonant(CHR(2)) {
                k = 1
                j = 1
                vowelStartIndex = 1
            }
            
            for _ in 0..<3 {
                if k < endIdx && !isConsonant(CHR(k)) {
                    k += 1
                    vowelEndIndex = UInt8(k)
                }
            }
            
            if k > j {
                spellingVowelOK = false
                if k - j > 1 && forceCheckVowel {
                    if let vowelSet = _vowelCombine[CHR(j)] {
                        for l in 0..<vowelSet.count {
                            spellingFlag = false
                            var ii = 1
                            while ii < vowelSet[l].count {
                                let targetIdx = j + ii - 1
                                if targetIdx < endIdx {
                                    let actual = UInt32(CHR(targetIdx)) | (typingWord[targetIdx] & TONEW_MASK) | (typingWord[targetIdx] & TONE_MASK)
                                    if vowelSet[l][ii] != actual {
                                        spellingFlag = true
                                        break
                                    }
                                }
                                ii += 1
                            }
                            if spellingFlag || (k < endIdx && vowelSet[l][0] == 0) || (j + ii - 1 < endIdx && !isConsonant(CHR(j + ii - 1))) {
                                continue
                            }
                            spellingVowelOK = true
                            break
                        }
                    }
                } else if !isConsonant(CHR(j)) {
                    spellingVowelOK = true
                }
                
                for ii in 0..<_endConsonantTable.count {
                    spellingFlag = false
                    for jElem in 0..<_endConsonantTable[ii].count {
                        if endIdx > k + jElem && _endConsonantTable[ii][jElem] != CHR(k + jElem) {
                            spellingFlag = true
                            break
                        }
                    }
                    if spellingFlag { continue }
                    if k + _endConsonantTable[ii].count >= endIdx {
                        spellingOK = true
                        break
                    }
                }
                
                if spellingOK {
                    if index >= 3 && CHR(Int(index) - 1) == KEY_H && CHR(Int(index) - 2) == KEY_C {
                        let wordTone = typingWord[Int(index) - 3]
                        let hasMark = (wordTone & MARK_MASK) != 0
                        let is1 = (wordTone & MARK1_MASK) != 0
                        let is5 = (wordTone & MARK5_MASK) != 0
                        if hasMark && !is1 && !is5 {
                            spellingOK = false
                        }
                    } else if index >= 2 && CHR(Int(index) - 1) == KEY_T {
                        let wordTone = typingWord[Int(index) - 2]
                        let hasMark = (wordTone & MARK_MASK) != 0
                        let is1 = (wordTone & MARK1_MASK) != 0
                        let is5 = (wordTone & MARK5_MASK) != 0
                        if hasMark && !is1 && !is5 {
                            spellingOK = false
                        }
                    }
                }
            }
        } else {
            spellingOK = true
        }
        
        tempDisableKey = !(spellingOK && spellingVowelOK)
    }
    
    // MARK: - Phonotactic Syllable Repair (REQ-002, ADR-002)
    
    @discardableResult
    private func repairPhonotacticClusterIfNeeded(isInsertingMark: Bool = false) -> Bool {
        guard vAutoWordingEnabled != 0 && vGrammarRepairEnabled != 0 else { return false }
        guard index >= 3 else { return false }
        
        findAndCalculateVowel(forGrammar: true)
        guard vowelCount >= 2 else { return false }
        
        var repaired = false
        let vsi = Int(vowelStartIndex)
        let vei = Int(vowelEndIndex)
        
        // Final consonant present after vowel span
        let hasFinalConsonant = (Int(index) - 1 > vei) && isConsonant(CHR(vei + 1))
        guard hasFinalConsonant else { return false }
        
        // Rule 1: ie/ye + final consonant -> iê/yê
        let prev = CHR(vei - 1)
        let curr = CHR(vei)
        if (prev == KEY_I || prev == KEY_Y) && curr == KEY_E {
            let prevIdx = vei - 1
            let currIdx = vei
            let hasToneOrInserting = isInsertingMark ||
                (typingWord[prevIdx] & MARK_MASK) != 0 ||
                (typingWord[currIdx] & MARK_MASK) != 0
            if hasToneOrInserting && (typingWord[vei] & TONE_MASK) == 0 {
                typingWord[vei] |= (TONE_MASK | AUTO_TONE_MASK)
                repaired = true
            }
        }
        
        // Rule 2: uow -> ươ (only c1 == KEY_U && c2 == KEY_O, skip if preceded by Q)
        if vei >= vsi + 1 {
            for i in vsi..<vei {
                let c1 = CHR(i)
                let c2 = CHR(i + 1)
                if c1 == KEY_U && c2 == KEY_O {
                    if i > 0 && CHR(i - 1) == KEY_Q { continue }
                    let m1 = typingWord[i] & TONEW_MASK
                    let m2 = typingWord[i + 1] & TONEW_MASK
                    if (m1 != 0 || m2 != 0) && (m1 == 0 || m2 == 0) {
                        if m1 == 0 { typingWord[i] |= (TONEW_MASK | AUTO_TONE_MASK) }
                        if m2 == 0 { typingWord[i + 1] |= (TONEW_MASK | AUTO_TONE_MASK) }
                        repaired = true
                    }
                }
            }
        }
        
        return repaired
    }
    
    // MARK: - Grammar Check
    
    private func checkGrammar(deltaBackSpace: Int) {
        guard index > 1 && Int(index) < maxBuff else { return }
        
        isCheckedGrammar = (deltaBackSpace <= 0) ? repairPhonotacticClusterIfNeeded(isInsertingMark: false) : false
        
        findAndCalculateVowel(forGrammar: true)
        guard vowelCount > 0 else { return }
        
        let l = Int(vowelStartIndex)
        
        if index >= 3 {
            for i in stride(from: Int(index) - 1, through: 0, by: -1) {
                let ch = CHR(i)
                if ch == KEY_N || ch == KEY_C || ch == KEY_I || ch == KEY_M || ch == KEY_P || ch == KEY_T {
                    if i - 2 >= 0 && CHR(i - 1) == KEY_O && CHR(i - 2) == KEY_U {
                        let mask1 = typingWord[i - 1] & TONEW_MASK
                        let mask2 = typingWord[i - 2] & TONEW_MASK
                        if mask1 ^ mask2 != 0 {
                            if (typingWord[i - 2] & TONEW_MASK) == 0 { typingWord[i - 2] |= (TONEW_MASK | AUTO_TONE_MASK) }
                            if (typingWord[i - 1] & TONEW_MASK) == 0 { typingWord[i - 1] |= (TONEW_MASK | AUTO_TONE_MASK) }
                            isCheckedGrammar = true
                            break
                        }
                    }
                }
            }
        }
        
        if index >= 2 {
            for i in l...Int(vowelEndIndex) {
                if (typingWord[i] & MARK_MASK) != 0 {
                    let mark = typingWord[i] & MARK_MASK
                    typingWord[i] &= ~MARK_MASK
                    insertMark(markMask: mark, canModifyFlag: false)
                    if i != Int(vowelWillSetMark) {
                        isCheckedGrammar = true
                    }
                    break
                }
            }
        }
        
        if isCheckedGrammar {
            if hookOutput.code == HookCodeState.doNothing {
                hookOutput.code = HookCodeState.willProcess
            }
            hookOutput.backspaceCount = 0
            
            for i in stride(from: Int(index) - 1, through: l, by: -1) {
                hookOutput.backspaceCount += 1
                hookOutput.charData[Int(index) - 1 - i] = GET(typingWord[i])
            }
            hookOutput.newCharCount = hookOutput.backspaceCount
            hookOutput.backspaceCount = UInt8(Int(hookOutput.backspaceCount) + deltaBackSpace)
            hookOutput.extCode = 4
        }
    }
    
    // MARK: - Syllable / Key Insertion
    
    private func insertKey(keyCode: UInt16, caps: Bool, isCheckSpellingFlag: Bool = true) {
        if Int(index) >= maxBuff {
            longWordHelper.append(typingWord[0])
            for iii in 0..<(maxBuff - 1) {
                typingWord[iii] = typingWord[iii + 1]
            }
            setKeyData(idx: Int(index) - 1, keyCode: keyCode, caps: caps)
        } else {
            setKeyData(idx: Int(index), keyCode: keyCode, caps: caps)
            index += 1
        }
        
        if vCheckSpelling != 0 && isCheckSpellingFlag {
            checkSpelling()
        }
        
        if keyCode == KEY_D && Int(index) - 2 >= 0 && isConsonant(CHR(Int(index) - 2)) {
            tempDisableKey = false
        }
    }
    
    private func insertState(keyCode: UInt16, caps: Bool) {
        if Int(stateIndex) >= maxBuff {
            for iii in 0..<(maxBuff - 1) {
                keyStates[iii] = keyStates[iii + 1]
            }
            keyStates[Int(stateIndex) - 1] = UInt32(keyCode) | (caps ? CAPS_MASK : 0)
        } else {
            keyStates[Int(stateIndex)] = UInt32(keyCode) | (caps ? CAPS_MASK : 0)
            stateIndex += 1
        }
    }
    
    private func saveWord() {
        if index > 0 {
            if !longWordHelper.isEmpty {
                typingStatesData.removeAll()
                for i in 0..<longWordHelper.count {
                    if i != 0 && i % maxBuff == 0 {
                        typingStates.append(typingStatesData)
                        typingStatesData.removeAll()
                    }
                    typingStatesData.append(longWordHelper[i])
                }
                typingStates.append(typingStatesData)
                longWordHelper.removeAll()
            }
            
            typingStatesData.removeAll()
            for i in 0..<Int(index) {
                typingStatesData.append(typingWord[i])
            }
            typingStates.append(typingStatesData)
        }
    }
    
    private func saveWord(keyCode: UInt32, count: Int) {
        typingStatesData.removeAll()
        for _ in 0..<count {
            typingStatesData.append(keyCode)
        }
        typingStates.append(typingStatesData)
    }
    
    private func saveSpecialChar() {
        typingStatesData.removeAll()
        for i in 0..<specialChar.count {
            typingStatesData.append(specialChar[i])
        }
        typingStates.append(typingStatesData)
        specialChar.removeAll()
    }
    
    private func restoreLastTypingState() {
        guard !typingStates.isEmpty else { return }
        typingStatesData = typingStates.removeLast()
        if !typingStatesData.isEmpty {
            if typingStatesData[0] == UInt32(KEY_SPACE) {
                spaceCount = typingStatesData.count
                index = 0
            } else if charKeyCode.contains(UInt16(typingStatesData[0] & CHAR_MASK)) {
                index = 0
                specialChar = typingStatesData
                checkSpelling()
            } else {
                for i in 0..<typingStatesData.count {
                    typingWord[i] = typingStatesData[i]
                    keyStates[i] = typingStatesData[i]
                }
                index = UInt8(typingStatesData.count)
                stateIndex = index
                for i in Int(index)..<maxBuff {
                    typingWord[i] = UInt32(KEY_EMPTY)
                    keyStates[i] = UInt32(KEY_EMPTY)
                }
                if vCheckSpelling != 0 {
                    checkSpelling()
                }
            }
        }
    }
    
    private func checkCorrectVowel(charset: [[UInt16]], i: Int, markKey: UInt16) {
        if index >= 2 && CHR(Int(index) - 1) == KEY_U && CHR(Int(index) - 2) == KEY_Q {
            isCorrect = false
            return
        }
        var k = Int(index) - 1
        for j in stride(from: charset[i].count - 1, through: 0, by: -1) {
            if charset[i][j] != CHR(k) {
                isCorrect = false
                return
            }
            k -= 1
            if k < 0 { break }
        }
        
        if isCorrect && charset[i].count > 1 && (isKeyF(markKey) || isKeyX(markKey) || isKeyR(markKey)) {
            if charset[i][1] == KEY_C || charset[i][1] == KEY_T {
                isCorrect = false
            } else if charset[i].count > 2 && charset[i][2] == KEY_T {
                isCorrect = false
            }
        }
        
        if isCorrect && k >= 0 {
            if CHR(k) == CHR(k + 1) {
                isCorrect = false
            }
        }
    }
    
    // MARK: - Vowel Calculation & Mark Positioning
    
    private func findAndCalculateVowel(forGrammar: Bool = false) {
        vowelCount = 0
        vowelStartIndex = 0
        vowelEndIndex = 0
        guard index > 0 else { return }
        
        for iii in stride(from: Int(index) - 1, through: 0, by: -1) {
            if isConsonant(CHR(iii)) {
                if vowelCount > 0 { break }
            } else {
                if vowelCount == 0 {
                    vowelEndIndex = UInt8(iii)
                }
                if !forGrammar {
                    if (iii - 1 >= 0 && (CHR(iii) == KEY_I && CHR(iii - 1) == KEY_G)) ||
                       (iii - 1 >= 0 && (CHR(iii) == KEY_U && CHR(iii - 1) == KEY_Q)) {
                        break
                    }
                }
                vowelStartIndex = UInt8(iii)
                vowelCount += 1
            }
        }
        if vowelStartIndex > 0 && CHR(Int(vowelStartIndex)) == KEY_U && CHR(Int(vowelStartIndex) - 1) == KEY_Q {
            vowelStartIndex += 1
            if vowelCount > 0 {
                vowelCount -= 1
            }
        }
    }
    
    private func removeMark() {
        findAndCalculateVowel(forGrammar: true)
        isChanged = false
        if index > 0 {
            for i in Int(vowelStartIndex)...Int(vowelEndIndex) {
                if (typingWord[i] & MARK_MASK) != 0 {
                    typingWord[i] &= ~MARK_MASK
                    isChanged = true
                }
            }
        }
        if isChanged {
            hookOutput.code = HookCodeState.willProcess
            hookOutput.backspaceCount = 0
            for i in stride(from: Int(index) - 1, through: Int(vowelStartIndex), by: -1) {
                hookOutput.backspaceCount += 1
                hookOutput.charData[Int(index) - 1 - i] = GET(typingWord[i])
            }
            hookOutput.newCharCount = hookOutput.backspaceCount
        } else {
            hookOutput.code = HookCodeState.doNothing
        }
    }
    
    private func canHasEndConsonant() -> Bool {
        guard let vo = _vowelCombine[CHR(Int(vowelStartIndex))] else { return false }
        for ii in 0..<vo.count {
            var kk = Int(vowelStartIndex)
            var iii = 1
            while iii < vo[ii].count {
                if kk > Int(vowelEndIndex) || ((UInt32(CHR(kk)) | (typingWord[kk] & TONE_MASK) | (typingWord[kk] & TONEW_MASK)) != vo[ii][iii]) {
                    break
                }
                kk += 1
                iii += 1
            }
            if iii >= vo[ii].count {
                return vo[ii][0] == 1
            }
        }
        return false
    }
    
    private func handleModernMark() {
        vowelWillSetMark = vowelEndIndex
        
        let vsi = Int(vowelStartIndex)
        let vei = Int(vowelEndIndex)
        
        if vowelCount == 3 && vsi + 2 <= vei && ((CHR(vsi) == KEY_O && CHR(vsi + 1) == KEY_A && CHR(vsi + 2) == KEY_I) ||
                               (CHR(vsi) == KEY_U && CHR(vsi + 1) == KEY_Y && CHR(vsi + 2) == KEY_U) ||
                               (CHR(vsi) == KEY_O && CHR(vsi + 1) == KEY_E && CHR(vsi + 2) == KEY_O) ||
                               (CHR(vsi) == KEY_U && CHR(vsi + 1) == KEY_Y && CHR(vsi + 2) == KEY_A)) {
            vowelWillSetMark = UInt8(vsi + 1)
        } else if vsi + 1 <= vei && (CHR(vsi) == KEY_O && CHR(vsi + 1) == KEY_I) ||
                  (CHR(vsi) == KEY_A && CHR(vsi + 1) == KEY_I) ||
                  (CHR(vsi) == KEY_U && CHR(vsi + 1) == KEY_I) {
            vowelWillSetMark = vowelStartIndex
        } else if vei > 0 && CHR(vei - 1) == KEY_A && CHR(vei) == KEY_Y {
            vowelWillSetMark = UInt8(vei - 1)
        } else if vsi + 1 <= vei && CHR(vsi) == KEY_U && CHR(vsi + 1) == KEY_O {
            vowelWillSetMark = UInt8(vsi + 1)
        } else if vsi + 1 <= vei && (CHR(vsi + 1) == KEY_O || CHR(vsi + 1) == KEY_U) {
            vowelWillSetMark = UInt8(vei - 1)
        } else if CHR(vsi) == KEY_O || CHR(vsi) == KEY_U {
            vowelWillSetMark = vowelEndIndex
        }
        
        // Rule 3.1
        let isRule3_1: Bool = {
            guard vsi + 1 <= vei else { return false }
            let chVsi = CHR(vsi)
            let w1 = typingWord[vsi + 1]
            if chVsi == KEY_I && CHR(vsi + 1) == KEY_E && (w1 & TONE_MASK) != 0 { return true }
            if chVsi == KEY_Y && CHR(vsi + 1) == KEY_E && (w1 & TONE_MASK) != 0 { return true }
            if chVsi == KEY_U && CHR(vsi + 1) == KEY_O && (w1 & TONE_MASK) != 0 { return true }
            if chVsi == KEY_U && (typingWord[vsi] & TONEW_MASK) != 0 && CHR(vsi + 1) == KEY_O && (w1 & TONEW_MASK) != 0 { return true }
            return false
        }()
        
        if isRule3_1 {
            if vsi + 2 < Int(index) {
                let ch2 = CHR(vsi + 2)
                if ch2 == KEY_P || ch2 == KEY_T || ch2 == KEY_M || ch2 == KEY_N ||
                   ch2 == KEY_O || ch2 == KEY_U || ch2 == KEY_I || ch2 == KEY_C ||
                   (vsi + 3 < Int(index) && ch2 == KEY_C && CHR(vsi + 3) == KEY_H) ||
                   (vsi + 3 < Int(index) && ch2 == KEY_N && CHR(vsi + 3) == KEY_H) ||
                   (vsi + 3 < Int(index) && ch2 == KEY_N && CHR(vsi + 3) == KEY_G) {
                    vowelWillSetMark = UInt8(vsi + 1)
                } else {
                    vowelWillSetMark = vowelStartIndex
                }
            } else {
                vowelWillSetMark = vowelStartIndex
            }
        } else if vsi + 1 <= vei && ((CHR(vsi) == KEY_I && CHR(vsi + 1) == KEY_A) ||
                  (CHR(vsi) == KEY_Y && CHR(vsi + 1) == KEY_A) ||
                  (CHR(vsi) == KEY_U && CHR(vsi + 1) == KEY_A) ||
                  ((CHR(vsi) == KEY_U && (typingWord[vsi] & TONEW_MASK) != 0 && CHR(vsi + 1) == KEY_U) ||
                   (CHR(vsi) == KEY_U && CHR(vsi + 1) == KEY_U && (typingWord[vsi + 1] & TONEW_MASK) != 0))) {
            vowelWillSetMark = vowelStartIndex
        }
        
        // Rule 4
        if vowelCount == 2 && vsi + 1 <= vei {
            if (CHR(vsi) == KEY_I && CHR(vsi + 1) == KEY_A) ||
               (CHR(vsi) == KEY_I && CHR(vsi + 1) == KEY_U) ||
               (CHR(vsi) == KEY_I && CHR(vsi + 1) == KEY_O) {
                if vsi == 0 || CHR(vsi - 1) != KEY_G {
                    vowelWillSetMark = vowelStartIndex
                } else {
                    vowelWillSetMark = UInt8(vsi + 1)
                }
            } else if CHR(vsi) == KEY_U && CHR(vsi + 1) == KEY_A {
                if vsi == 0 || CHR(vsi - 1) != KEY_Q {
                    if vei + 1 >= Int(index) || !canHasEndConsonant() {
                        vowelWillSetMark = vowelStartIndex
                    }
                } else {
                    vowelWillSetMark = UInt8(vsi + 1)
                }
            } else if CHR(vsi) == KEY_O && CHR(vsi + 1) == KEY_O {
                vowelWillSetMark = vowelEndIndex
            }
        }
    }
    
    private func handleOldMark() {
        if vowelCount == 0 && CHR(Int(vowelEndIndex)) == KEY_I {
            vowelWillSetMark = vowelEndIndex
        } else {
            vowelWillSetMark = vowelStartIndex
        }
        
        let vsi = Int(vowelStartIndex)
        let vei = Int(vowelEndIndex)
        
        if vowelCount == 3 || (vei + 1 < Int(index) && isConsonant(CHR(vei + 1)) && canHasEndConsonant()) {
            vowelWillSetMark = UInt8(vsi + 1)
        }
        
        for ii in vsi...vei {
            if (CHR(ii) == KEY_E && (typingWord[ii] & TONE_MASK) != 0) ||
               (CHR(ii) == KEY_O && (typingWord[ii] & TONEW_MASK) != 0) {
                vowelWillSetMark = UInt8(ii)
                break
            }
        }
    }
    
    private func insertMark(markMask: UInt32, canModifyFlag: Bool = true) {
        if canModifyFlag {
            repairPhonotacticClusterIfNeeded(isInsertingMark: true)
        }
        vowelCount = 0
        if canModifyFlag {
            hookOutput.code = HookCodeState.willProcess
            hookOutput.backspaceCount = 0
            hookOutput.newCharCount = 0
        }
        
        findAndCalculateVowel()
        vowelWillSetMark = 0
        
        if vowelCount == 1 {
            vowelWillSetMark = vowelEndIndex
        } else {
            if vUseModernOrthography == 0 {
                handleOldMark()
            } else {
                handleModernMark()
            }
            let vei = Int(vowelEndIndex)
            if (typingWord[vei] & TONE_MASK) != 0 || (typingWord[vei] & TONEW_MASK) != 0 {
                vowelWillSetMark = vowelEndIndex
            }
        }
        
        let vsi = Int(vowelStartIndex)
        let vwsm = Int(vowelWillSetMark)
        var kk = Int(index) - 1 - vsi
        
        if (typingWord[vwsm] & markMask) != 0 {
            typingWord[vwsm] &= ~MARK_MASK
            if canModifyFlag {
                hookOutput.code = HookCodeState.restore
                for ii in vsi..<Int(index) {
                    typingWord[ii] &= ~MARK_MASK
                    if (typingWord[ii] & AUTO_TONE_MASK) != 0 {
                        typingWord[ii] &= ~(TONE_MASK | TONEW_MASK | AUTO_TONE_MASK)
                    }
                    if kk >= 0 {
                        hookOutput.charData[kk] = GET(typingWord[ii])
                        kk -= 1
                    }
                }
                tempDisableKey = true
                hookOutput.backspaceCount = UInt8(Int(index) - vsi)
                hookOutput.newCharCount = hookOutput.backspaceCount
            } else {
                for ii in vsi..<Int(index) {
                    typingWord[ii] &= ~MARK_MASK
                    if (typingWord[ii] & AUTO_TONE_MASK) != 0 {
                        typingWord[ii] &= ~(TONE_MASK | TONEW_MASK | AUTO_TONE_MASK)
                    }
                }
            }
        } else {
            typingWord[vwsm] &= ~MARK_MASK
            typingWord[vwsm] |= markMask
            if canModifyFlag {
                for ii in vsi..<Int(index) {
                    if ii != vwsm {
                        typingWord[ii] &= ~MARK_MASK
                    }
                    if kk >= 0 {
                        hookOutput.charData[kk] = GET(typingWord[ii])
                        kk -= 1
                    }
                }
                hookOutput.backspaceCount = UInt8(Int(index) - vsi)
                hookOutput.newCharCount = hookOutput.backspaceCount
                tempDisableKey = false
            } else {
                for ii in vsi..<Int(index) {
                    if ii != vwsm {
                        typingWord[ii] &= ~MARK_MASK
                    }
                }
            }
        }
    }
    
    private func insertD(data: UInt16, caps: Bool) {
        hookOutput.code = HookCodeState.willProcess
        hookOutput.backspaceCount = 0
        guard index > 0 else { return }
        for ii in stride(from: Int(index) - 1, through: 0, by: -1) {
            hookOutput.backspaceCount += 1
            if CHR(ii) == KEY_D {
                if (typingWord[ii] & TONE_MASK) != 0 {
                    hookOutput.code = HookCodeState.restore
                    typingWord[ii] &= ~TONE_MASK
                    hookOutput.charData[Int(index) - 1 - ii] = GET(typingWord[ii])
                    tempDisableKey = true
                    break
                } else {
                    typingWord[ii] |= TONE_MASK
                    hookOutput.charData[Int(index) - 1 - ii] = GET(typingWord[ii])
                }
                break
            } else {
                hookOutput.charData[Int(index) - 1 - ii] = GET(typingWord[ii])
            }
        }
        hookOutput.newCharCount = hookOutput.backspaceCount
    }
    
    private func insertAOE(data: UInt16, caps: Bool) {
        findAndCalculateVowel()
        let vsi = Int(vowelStartIndex)
        let vei = Int(vowelEndIndex)
        if vsi <= vei {
            for ii in vsi...vei {
                typingWord[ii] &= ~TONEW_MASK
            }
        }
        
        hookOutput.code = HookCodeState.willProcess
        hookOutput.backspaceCount = 0
        guard index > 0 else { return }
        
        for ii in stride(from: Int(index) - 1, through: 0, by: -1) {
            hookOutput.backspaceCount += 1
            if CHR(ii) == data {
                if (typingWord[ii] & TONE_MASK) != 0 {
                    if (typingWord[ii] & AUTO_TONE_MASK) != 0 {
                        typingWord[ii] &= ~AUTO_TONE_MASK
                        hookOutput.code = HookCodeState.willProcess
                        hookOutput.charData[Int(index) - 1 - ii] = GET(typingWord[ii])
                        break
                    }
                    hookOutput.code = HookCodeState.restore
                    typingWord[ii] &= ~TONE_MASK
                    hookOutput.charData[Int(index) - 1 - ii] = GET(typingWord[ii])
                    if data != KEY_O {
                        tempDisableKey = true
                    }
                    break
                } else {
                    typingWord[ii] |= TONE_MASK
                    if !isKeyD(data) {
                        typingWord[ii] &= ~TONEW_MASK
                    }
                    hookOutput.charData[Int(index) - 1 - ii] = GET(typingWord[ii])
                }
                break
            } else {
                hookOutput.charData[Int(index) - 1 - ii] = GET(typingWord[ii])
            }
        }
        hookOutput.newCharCount = hookOutput.backspaceCount
    }
    
    private func insertW(data: UInt16, caps: Bool) {
        isRestoredW = false
        findAndCalculateVowel()
        let vsi = Int(vowelStartIndex)
        let vei = Int(vowelEndIndex)
        if vsi <= vei {
            for ii in vsi...vei {
                typingWord[ii] &= ~TONE_MASK
            }
        }
        
        if vowelCount > 1 {
            hookOutput.backspaceCount = UInt8(Int(index) - vsi)
            hookOutput.newCharCount = hookOutput.backspaceCount
            
            let hasW0 = (typingWord[vsi] & TONEW_MASK) != 0
            let hasW1 = vsi + 1 < maxBuff && (typingWord[vsi + 1] & TONEW_MASK) != 0
            let ch1 = vsi + 1 < maxBuff ? CHR(vsi + 1) : 0
            
            if (hasW0 && hasW1) || (hasW0 && ch1 == KEY_I) || (hasW0 && ch1 == KEY_A) {
                if (typingWord[vsi] & AUTO_TONE_MASK) != 0 || (vsi + 1 < maxBuff && (typingWord[vsi + 1] & AUTO_TONE_MASK) != 0) {
                    typingWord[vsi] &= ~AUTO_TONE_MASK
                    if vsi + 1 < maxBuff { typingWord[vsi + 1] &= ~AUTO_TONE_MASK }
                    hookOutput.code = HookCodeState.willProcess
                    for ii in vsi..<Int(index) {
                        hookOutput.charData[Int(index) - 1 - ii] = GET(typingWord[ii])
                    }
                } else {
                    hookOutput.code = HookCodeState.restore
                    for ii in vsi..<Int(index) {
                        typingWord[ii] &= ~TONEW_MASK
                        hookOutput.charData[Int(index) - 1 - ii] = GET(typingWord[ii]) & ~STANDALONE_MASK
                    }
                    isRestoredW = true
                    tempDisableKey = true
                }
            } else {
                hookOutput.code = HookCodeState.willProcess
                let ch0 = CHR(vsi)
                if ch0 == KEY_U && ch1 == KEY_O {
                    if vsi - 2 >= 0 && CHR(vsi - 2) == KEY_T && CHR(vsi - 1) == KEY_H {
                        typingWord[vsi + 1] |= TONEW_MASK
                        if vsi + 2 < Int(index) && CHR(vsi + 2) == KEY_N {
                            typingWord[vsi] |= TONEW_MASK
                        }
                    } else if vsi - 1 >= 0 && CHR(vsi - 1) == KEY_Q {
                        typingWord[vsi + 1] |= TONEW_MASK
                    } else {
                        typingWord[vsi] |= TONEW_MASK
                        typingWord[vsi + 1] |= TONEW_MASK
                    }
                } else if (ch0 == KEY_U && ch1 == KEY_A) ||
                          (ch0 == KEY_U && ch1 == KEY_I) ||
                          (ch0 == KEY_U && ch1 == KEY_U) ||
                          (ch0 == KEY_O && ch1 == KEY_I) {
                    typingWord[vsi] |= TONEW_MASK
                } else if (ch0 == KEY_I && ch1 == KEY_O) ||
                          (ch0 == KEY_O && ch1 == KEY_A) {
                    typingWord[vsi + 1] |= TONEW_MASK
                } else {
                    tempDisableKey = true
                    isChanged = false
                    hookOutput.code = HookCodeState.doNothing
                }
                
                for ii in vsi..<Int(index) {
                    hookOutput.charData[Int(index) - 1 - ii] = GET(typingWord[ii])
                }
            }
            return
        }
        
        hookOutput.code = HookCodeState.willProcess
        hookOutput.backspaceCount = 0
        guard index > 0 else { return }
        
        for ii in stride(from: Int(index) - 1, through: 0, by: -1) {
            if ii < vsi { break }
            hookOutput.backspaceCount += 1
            let ch = CHR(ii)
            switch ch {
            case KEY_A, KEY_U, KEY_O:
                if (typingWord[ii] & TONEW_MASK) != 0 {
                    if (typingWord[ii] & AUTO_TONE_MASK) != 0 {
                        typingWord[ii] &= ~AUTO_TONE_MASK
                        hookOutput.code = HookCodeState.willProcess
                        hookOutput.charData[Int(index) - 1 - ii] = GET(typingWord[ii])
                    } else if (typingWord[ii] & STANDALONE_MASK) != 0 {
                        hookOutput.code = HookCodeState.willProcess
                        if ch == KEY_U {
                            typingWord[ii] = UInt32(KEY_W) | (((typingWord[ii] & CAPS_MASK) != 0) ? CAPS_MASK : 0)
                        } else if ch == KEY_O {
                            hookOutput.code = HookCodeState.restore
                            typingWord[ii] = UInt32(KEY_O) | (((typingWord[ii] & CAPS_MASK) != 0) ? CAPS_MASK : 0)
                            isRestoredW = true
                        }
                        hookOutput.charData[Int(index) - 1 - ii] = GET(typingWord[ii])
                    } else {
                        hookOutput.code = HookCodeState.restore
                        typingWord[ii] &= ~TONEW_MASK
                        hookOutput.charData[Int(index) - 1 - ii] = GET(typingWord[ii])
                        isRestoredW = true
                    }
                    tempDisableKey = true
                } else {
                    typingWord[ii] |= TONEW_MASK
                    typingWord[ii] &= ~TONE_MASK
                    hookOutput.charData[Int(index) - 1 - ii] = GET(typingWord[ii])
                }
            default:
                hookOutput.charData[Int(index) - 1 - ii] = GET(typingWord[ii])
            }
        }
        hookOutput.newCharCount = hookOutput.backspaceCount
    }
    
    private func reverseLastStandaloneChar(keyCode: UInt32, caps: Bool) {
        hookOutput.code = HookCodeState.willProcess
        hookOutput.backspaceCount = 0
        hookOutput.newCharCount = 1
        hookOutput.extCode = 4
        typingWord[Int(index) - 1] = keyCode | TONEW_MASK | STANDALONE_MASK | (caps ? CAPS_MASK : 0)
        hookOutput.charData[0] = GET(typingWord[Int(index) - 1])
    }
    
    private func checkForStandaloneChar(data: UInt16, caps: Bool, keyWillReverse: UInt32) {
        if index > 0 && CHR(Int(index) - 1) == UInt16(keyWillReverse) && ((typingWord[Int(index) - 1] & TONEW_MASK) != 0) {
            hookOutput.code = HookCodeState.willProcess
            hookOutput.backspaceCount = 1
            hookOutput.newCharCount = 1
            typingWord[Int(index) - 1] = UInt32(data) | (caps ? CAPS_MASK : 0)
            hookOutput.charData[0] = GET(typingWord[Int(index) - 1])
            return
        }
        
        if index > 0 && CHR(Int(index) - 1) == KEY_U && keyWillReverse == UInt32(KEY_O) {
            insertKey(keyCode: UInt16(keyWillReverse), caps: caps)
            reverseLastStandaloneChar(keyCode: keyWillReverse, caps: caps)
            return
        }
        
        if index == 0 {
            insertKey(keyCode: data, caps: caps, isCheckSpellingFlag: false)
            reverseLastStandaloneChar(keyCode: keyWillReverse, caps: caps)
            return
        } else if index == 1 {
            for i in 0..<_standaloneWbad.count {
                if CHR(0) == _standaloneWbad[i] {
                    insertKey(keyCode: data, caps: caps)
                    return
                }
            }
            insertKey(keyCode: data, caps: caps, isCheckSpellingFlag: false)
            reverseLastStandaloneChar(keyCode: keyWillReverse, caps: caps)
            return
        } else if index == 2 {
            for i in 0..<_doubleWAllowed.count {
                if CHR(0) == _doubleWAllowed[i][0] && CHR(1) == _doubleWAllowed[i][1] {
                    insertKey(keyCode: data, caps: caps, isCheckSpellingFlag: false)
                    reverseLastStandaloneChar(keyCode: keyWillReverse, caps: caps)
                    return
                }
            }
            insertKey(keyCode: data, caps: caps)
            return
        }
        
        insertKey(keyCode: data, caps: caps)
    }
    
    private func handleMainKey(data: UInt16, caps: Bool) {
        if isKeyZ(data) {
            removeMark()
            if !isChanged {
                insertKey(keyCode: data, caps: caps)
            }
            return
        }
        
        if data == KEY_LEFT_BRACKET {
            checkForStandaloneChar(data: data, caps: caps, keyWillReverse: UInt32(KEY_O))
            return
        }
        if data == KEY_RIGHT_BRACKET {
            checkForStandaloneChar(data: data, caps: caps, keyWillReverse: UInt32(KEY_U))
            return
        }
        
        if isKeyD(data) {
            isCorrect = false
            isChanged = false
            for i in 0..<_consonantD.count {
                if Int(index) < _consonantD[i].count { continue }
                isCorrect = true
                checkCorrectVowel(charset: _consonantD, i: i, markKey: data)
                if !isCorrect && index >= 2 && CHR(Int(index) - 1) == KEY_D && isConsonant(CHR(Int(index) - 2)) {
                    isCorrect = true
                }
                if isCorrect {
                    isChanged = true
                    insertD(data: data, caps: caps)
                    break
                }
            }
            if !isChanged {
                insertKey(keyCode: data, caps: caps)
            }
            return
        }
        
        if isMarkKey(data) {
            for (_, charset) in _vowelForMark {
                isCorrect = false
                isChanged = false
                for l in 0..<charset.count {
                    if Int(index) < charset[l].count { continue }
                    isCorrect = true
                    checkCorrectVowel(charset: charset, i: l, markKey: data)
                    if isCorrect {
                        isChanged = true
                        if isKeyS(data) { insertMark(markMask: MARK1_MASK) }
                        else if isKeyF(data) { insertMark(markMask: MARK2_MASK) }
                        else if isKeyR(data) { insertMark(markMask: MARK3_MASK) }
                        else if isKeyX(data) { insertMark(markMask: MARK4_MASK) }
                        else if isKeyJ(data) { insertMark(markMask: MARK5_MASK) }
                        break
                    }
                }
                if isCorrect { break }
            }
            if !isChanged {
                insertKey(keyCode: data, caps: caps)
            }
            return
        }
        
        if vInputType == 1 { // VNI
            for i in stride(from: Int(index) - 1, through: 0, by: -1) {
                let ch = CHR(i)
                if ch == KEY_O || ch == KEY_A || ch == KEY_E {
                    vowelEndIndex = UInt8(i)
                    break
                }
            }
        }
        
        if vInputType != 1 {
            keyForAEO = data
        } else {
            if data == KEY_7 || data == KEY_8 {
                keyForAEO = KEY_W
            } else if data == KEY_6 {
                keyForAEO = CHR(Int(vowelEndIndex))
            } else {
                keyForAEO = data
            }
        }
        
        if let charset = _vowel[keyForAEO] {
            isCorrect = false
            isChanged = false
            for i in 0..<charset.count {
                if Int(index) < charset[i].count { continue }
                isCorrect = true
                checkCorrectVowel(charset: charset, i: i, markKey: data)
                if isCorrect {
                    isChanged = true
                    if isKeyDouble(data) {
                        insertAOE(data: keyForAEO, caps: caps)
                    } else if isKeyW(data) {
                        if vInputType == 1 {
                            for j in stride(from: Int(index) - 1, through: 0, by: -1) {
                                let ch = CHR(j)
                                if ch == KEY_O || ch == KEY_U || ch == KEY_A || ch == KEY_E {
                                    vowelEndIndex = UInt8(j)
                                    break
                                }
                            }
                            let vei = Int(vowelEndIndex)
                            let chVei = CHR(vei)
                            if (data == KEY_7 && chVei == KEY_A && (vei - 1 >= 0 ? CHR(vei - 1) != KEY_U : true)) ||
                               (data == KEY_8 && (chVei == KEY_O || chVei == KEY_U)) {
                                break
                            }
                        }
                        insertW(data: keyForAEO, caps: caps)
                    }
                    break
                }
            }
        }
        
        if !isChanged {
            if data == KEY_W && vInputType == 0 {
                checkForStandaloneChar(data: data, caps: caps, keyWillReverse: UInt32(KEY_U))
            } else {
                insertKey(keyCode: data, caps: caps)
            }
        }
    }
    
    private func checkRestoreIfWrongSpelling(handleCode: UInt8) -> Bool {
        guard index > 0 else { return false }
        for ii in 0..<Int(index) {
            let hasMarkOrTone = ((typingWord[ii] & MARK_MASK) != 0 || (typingWord[ii] & TONE_MASK) != 0 || (typingWord[ii] & TONEW_MASK) != 0)
            if hasMarkOrTone {
                hookOutput.code = handleCode
                hookOutput.backspaceCount = index
                hookOutput.newCharCount = stateIndex
                for i in 0..<Int(stateIndex) {
                    typingWord[i] = keyStates[i]
                    hookOutput.charData[Int(stateIndex) - 1 - i] = GET(typingWord[i])
                }
                index = stateIndex
                tempDisableKey = false
                return true
            }
        }
        return false
    }
    
    // MARK: - Event Dispatcher
    
    func handleKeyEvent(keyCode: UInt16, capsStatus: UInt8, otherControlKey: Bool) -> OKHookSnapshot {
        lock.lock()
        defer { lock.unlock() }
        
        hookOutput.code = HookCodeState.doNothing
        hookOutput.backspaceCount = 0
        hookOutput.newCharCount = 0
        hookOutput.extCode = 0
        hookOutput.charData[0] = 0
        
        let isAlphaKey = !isNumberKey(keyCode) && !charKeyCode.contains(keyCode)
        isCaps = (capsStatus == 1) || (capsStatus == 2 && isAlphaKey)
        
        if (isNumberKey(keyCode) && capsStatus == 1) || otherControlKey || isWordBreak(isMouse: false, data: keyCode) || (index == 0 && isNumberKey(keyCode)) {
            hookOutput.code = HookCodeState.doNothing
            hookOutput.backspaceCount = 0
            hookOutput.newCharCount = 0
            hookOutput.extCode = 1 // Word break
            
            if vRestoreIfWrongSpelling != 0 && isWordBreak(isMouse: false, data: keyCode) {
                if !tempDisableKey && vCheckSpelling != 0 {
                    checkSpelling(forceCheckVowel: true)
                }
                if tempDisableKey && !checkRestoreIfWrongSpelling(handleCode: HookCodeState.restoreAndStartNewSession) {
                    hookOutput.code = HookCodeState.doNothing
                }
            }
            
            isCharKeyCode = charKeyCode.contains(keyCode)
            if !isCharKeyCode {
                specialChar.removeAll()
                typingStates.removeAll()
            } else {
                if spaceCount > 0 {
                    saveWord(keyCode: UInt32(KEY_SPACE), count: spaceCount)
                    spaceCount = 0
                } else {
                    saveWord()
                }
                specialChar.append(UInt32(keyCode) | (isCaps ? CAPS_MASK : 0))
                hookOutput.extCode = 3
            }
            
            if hookOutput.code == HookCodeState.doNothing {
                startNewSessionInternal()
                vCheckSpelling = useSpellCheckingBefore
                willTempOffEngine = false
            }
        } else if keyCode == KEY_SPACE {
            // REQ-003: Vietnamese Shorthand Auto-Expansion on Space
            if vAutoWordingEnabled != 0 && vShorthandExpansionEnabled != 0 && spaceCount == 0 && index > 0 {
                let currentWord = getComposedWord()
                if let expanded = AutoWordingEngine.shared.expandShorthand(rawWord: currentWord) {
                    let fullText = expanded + " "
                    let utf16 = Array(fullText.utf16)
                    let bs = index
                    startNewSessionInternal()
                    typingStates.removeAll()
                    typingStatesData.removeAll()
                    specialChar.removeAll()
                    spaceCount = 1
                    willTempOffEngine = false
                    vCheckSpelling = useSpellCheckingBefore
                    
                    hookOutput.code = HookCodeState.willProcess
                    hookOutput.backspaceCount = bs
                    hookOutput.newCharCount = UInt8(utf16.count)
                    for i in 0..<utf16.count {
                        hookOutput.charData[utf16.count - 1 - i] = PURE_CHARACTER_MASK | UInt32(utf16[i])
                    }
                    hookOutput.extCode = 4
                    
                    if vCandidateSuggestionsEnabled != 0 {
                        let nextCands = AutoWordingEngine.shared.computeNextWordCandidates(previousWord: expanded)
                        AutoWordingEngine.shared.updateCandidates(nextCands)
                    }
                    
                    return OKHookSnapshot(
                        code: hookOutput.code,
                        backspaceCount: hookOutput.backspaceCount,
                        newCharCount: hookOutput.newCharCount,
                        extCode: hookOutput.extCode,
                        shouldSendControlKey: false,
                        utf16Chars: utf16
                    )
                }
            }
            
            let previousWordForNextPrediction = getComposedWord()
            
            if !tempDisableKey && vCheckSpelling != 0 {
                checkSpelling(forceCheckVowel: true)
            }
            if vRestoreIfWrongSpelling != 0 && tempDisableKey {
                if !checkRestoreIfWrongSpelling(handleCode: HookCodeState.restore) {
                    hookOutput.code = HookCodeState.doNothing
                }
                spaceCount += 1
            } else {
                hookOutput.code = HookCodeState.doNothing
                spaceCount += 1
            }
            
            if spaceCount == 1 {
                if !specialChar.isEmpty {
                    saveSpecialChar()
                } else {
                    saveWord()
                }
            }
            vCheckSpelling = useSpellCheckingBefore
            willTempOffEngine = false
            
            if vAutoWordingEnabled != 0 && vCandidateSuggestionsEnabled != 0 && !previousWordForNextPrediction.isEmpty {
                let nextCands = AutoWordingEngine.shared.computeNextWordCandidates(previousWord: previousWordForNextPrediction)
                AutoWordingEngine.shared.updateCandidates(nextCands)
            }
        } else if keyCode == KEY_DELETE {
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
                    restoreLastTypingState()
                }
            } else {
                if stateIndex > 0 {
                    stateIndex -= 1
                }
                if index > 0 {
                    index -= 1
                    typingWord[Int(index)] = UInt32(KEY_EMPTY)
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
                    let anyRemainingModified = (0..<Int(index)).contains { (typingWord[$0] & (MARK_MASK | TONE_MASK | TONEW_MASK)) != 0 }
                    if !anyRemainingModified {
                        stateIndex = index
                        for i in 0..<Int(index) {
                            keyStates[i] = typingWord[i]
                        }
                        for i in Int(index)..<maxBuff {
                            keyStates[i] = UInt32(KEY_EMPTY)
                        }
                    }
                }
                
                hookOutput.backspaceCount = 0
                hookOutput.newCharCount = 0
                hookOutput.extCode = 2
                if index == 0 {
                    stateIndex = 0
                    longWordHelper.removeAll()
                    startNewSessionInternal()
                    specialChar.removeAll()
                    restoreLastTypingState()
                } else {
                    checkGrammar(deltaBackSpace: 1)
                }
            }
        } else {
            if willTempOffEngine {
                hookOutput.code = HookCodeState.doNothing
                hookOutput.extCode = 3
                return OKHookSnapshot(code: 0, backspaceCount: 0, newCharCount: 0, extCode: 3, shouldSendControlKey: false, utf16Chars: [])
            }
            
            if spaceCount > 0 {
                hookOutput.backspaceCount = 0
                hookOutput.newCharCount = 0
                hookOutput.extCode = 0
                startNewSessionInternal()
                saveWord(keyCode: UInt32(KEY_SPACE), count: spaceCount)
                spaceCount = 0
            } else if !specialChar.isEmpty {
                saveSpecialChar()
            }
            
            insertState(keyCode: keyCode, caps: isCaps)
            
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
                if hookOutput.code == HookCodeState.doNothing {
                    checkGrammar(deltaBackSpace: -1)
                } else {
                    checkGrammar(deltaBackSpace: 0)
                }
            }
            
            if hookOutput.code == HookCodeState.restore {
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
                hookOutput.extCode = 3
                specialChar.append(UInt32(keyCode) | (isCaps ? CAPS_MASK : 0))
            }
        }
        
        if hookOutput.code == HookCodeState.doNothing {
            if vAutoWordingEnabled != 0 && vCandidateSuggestionsEnabled != 0 {
                if keyCode == KEY_DELETE || (index == 0 && keyCode != KEY_SPACE) {
                    AutoWordingEngine.shared.clearCandidates()
                }
            }
            return OKHookSnapshot(
                code: HookCodeState.doNothing,
                backspaceCount: 0,
                newCharCount: 0,
                extCode: hookOutput.extCode,
                shouldSendControlKey: false,
                utf16Chars: []
            )
        }
        
        // Assemble pure Swift snapshot
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
            if keyCodeToCharacter(UInt32(keyCode)) != 0 {
                let c = keyCodeToCharacter(UInt32(keyCode) | (isCaps ? CAPS_MASK : 0))
                chars.append(c)
            } else {
                shouldSendControl = true
            }
            if hookOutput.code == HookCodeState.restoreAndStartNewSession {
                startNewSessionInternal()
            }
        }
        
        // REQ-004: Update live word candidates
        if vAutoWordingEnabled != 0 && vCandidateSuggestionsEnabled != 0 {
            if keyCode != KEY_SPACE && keyCode != KEY_DELETE && hookOutput.code != HookCodeState.restore && hookOutput.code != HookCodeState.restoreAndStartNewSession {
                var rawStem = ""
                for i in 0..<Int(stateIndex) {
                    let ch = keyCodeToCharacter(keyStates[i])
                    if ch != 0, let scalar = UnicodeScalar(ch) {
                        rawStem.append(Character(scalar))
                    }
                }
                let composedText = getComposedWord()
                if rawStem.count >= 2 || composedText.count >= 2 {
                    let candidates = AutoWordingEngine.shared.computeCurrentWordCandidates(
                        rawStem: rawStem,
                        currentSyllable: composedText,
                        isWrongSpelling: tempDisableKey
                    )
                    if !candidates.isEmpty {
                        AutoWordingEngine.shared.updateCandidates(candidates)
                    } else {
                        AutoWordingEngine.shared.clearCandidates()
                    }
                } else {
                    AutoWordingEngine.shared.clearCandidates()
                }
            } else {
                AutoWordingEngine.shared.clearCandidates()
            }
        }
        
        return OKHookSnapshot(
            code: hookOutput.code,
            backspaceCount: hookOutput.backspaceCount,
            newCharCount: UInt8(chars.count),
            extCode: hookOutput.extCode,
            shouldSendControlKey: shouldSendControl,
            utf16Chars: chars
        )
    }
    
    // MARK: - Smart Switch Key Binary Persistence
    
    func initSmartSwitchKey(data: UnsafePointer<UInt8>?, size: Int32) {
        lock.lock()
        defer { lock.unlock() }
        smartSwitchData.removeAll()
        guard let pData = data, size >= 2 else { return }
        
        let count = UInt16(pData[0]) | (UInt16(pData[1]) << 8)
        var cursor = 2
        let totalSize = Int(size)
        
        for _ in 0..<count {
            if cursor >= totalSize { break }
            let bundleIdSize = Int(pData[cursor])
            cursor += 1
            if cursor + bundleIdSize + 1 > totalSize { break }
            
            let idData = Data(bytes: pData.advanced(by: cursor), count: bundleIdSize)
            cursor += bundleIdSize
            let value = Int8(bitPattern: pData[cursor])
            cursor += 1
            
            if let str = String(data: idData, encoding: .utf8) {
                smartSwitchData[str] = value
            }
        }
    }
    
    func getSmartSwitchKeySaveData(outBuffer: UnsafeMutablePointer<UInt8>?, maxBufferSize: Int32) -> Int32 {
        lock.lock()
        defer { lock.unlock() }
        
        var bytes: [UInt8] = []
        let count = UInt16(smartSwitchData.count)
        bytes.append(UInt8(count & 0xFF))
        bytes.append(UInt8((count >> 8) & 0xFF))
        
        for (bundleId, value) in smartSwitchData {
            let utf8Bytes = Array(bundleId.utf8)
            bytes.append(UInt8(utf8Bytes.count))
            bytes.append(contentsOf: utf8Bytes)
            bytes.append(UInt8(bitPattern: value))
        }
        
        let total = Int32(bytes.count)
        if let buffer = outBuffer, maxBufferSize > 0 {
            let toCopy = min(Int(maxBufferSize), bytes.count)
            buffer.initialize(from: bytes, count: toCopy)
        }
        return total
    }
    
    func getAppInputMethodStatus(bundleId: String, currentInputMethod: Int32) -> Int32 {
        lock.lock()
        defer { lock.unlock() }
        if smartSwitchCacheKey == bundleId {
            return Int32(smartSwitchCacheData)
        }
        if let found = smartSwitchData[bundleId] {
            smartSwitchCacheKey = bundleId
            smartSwitchCacheData = found
            return Int32(found)
        }
        smartSwitchCacheKey = bundleId
        smartSwitchCacheData = Int8(currentInputMethod)
        smartSwitchData[bundleId] = smartSwitchCacheData
        return -1
    }
    
    func setAppInputMethodStatus(bundleId: String, language: Int32) {
        lock.lock()
        defer { lock.unlock() }
        smartSwitchData[bundleId] = Int8(language)
        smartSwitchCacheKey = bundleId
        smartSwitchCacheData = Int8(language)
    }
    
    func syncConfig(
        language: Int32,
        inputType: Int32,
        checkSpelling: Int32,
        useModernOrthography: Int32,
        restoreIfWrongSpelling: Int32,
        fixRecommendBrowser: Int32,
        useSmartSwitchKey: Int32,
        autoWordingEnabled: Int32,
        grammarRepairEnabled: Int32,
        shorthandExpansionEnabled: Int32,
        candidateSuggestionsEnabled: Int32
    ) {
        lock.lock()
        defer { lock.unlock() }
        vLanguage = Int(language)
        vInputType = Int(inputType)
        vCheckSpelling = Int(checkSpelling)
        vUseModernOrthography = Int(useModernOrthography)
        vRestoreIfWrongSpelling = Int(restoreIfWrongSpelling)
        vFixRecommendBrowser = Int(fixRecommendBrowser)
        vUseSmartSwitchKey = Int(useSmartSwitchKey)
        vAutoWordingEnabled = Int(autoWordingEnabled)
        vGrammarRepairEnabled = Int(grammarRepairEnabled)
        vShorthandExpansionEnabled = Int(shorthandExpansionEnabled)
        vCandidateSuggestionsEnabled = Int(candidateSuggestionsEnabled)
    }
}

// MARK: - Public Pure Swift API Surface (Drop-in Parity with C++ Bridge)

public func OKEngineInit() {
    VietnameseEngineState.shared.initEngine()
}

public func OKEngineSyncConfig(
    _ language: Int32,
    _ inputType: Int32,
    _ checkSpelling: Int32,
    _ useModernOrthography: Int32,
    _ restoreIfWrongSpelling: Int32,
    _ fixRecommendBrowser: Int32,
    _ useSmartSwitchKey: Int32,
    _ autoWordingEnabled: Int32 = 0,
    _ grammarRepairEnabled: Int32 = 0,
    _ shorthandExpansionEnabled: Int32 = 0,
    _ candidateSuggestionsEnabled: Int32 = 0
) {
    VietnameseEngineState.shared.syncConfig(
        language: language,
        inputType: inputType,
        checkSpelling: checkSpelling,
        useModernOrthography: useModernOrthography,
        restoreIfWrongSpelling: restoreIfWrongSpelling,
        fixRecommendBrowser: fixRecommendBrowser,
        useSmartSwitchKey: useSmartSwitchKey,
        autoWordingEnabled: autoWordingEnabled,
        grammarRepairEnabled: grammarRepairEnabled,
        shorthandExpansionEnabled: shorthandExpansionEnabled,
        candidateSuggestionsEnabled: candidateSuggestionsEnabled
    )
    
    AutoWordingEngine.shared.isEnabled = (autoWordingEnabled != 0)
    AutoWordingEngine.shared.grammarRepairEnabled = (grammarRepairEnabled != 0)
    AutoWordingEngine.shared.shorthandExpansionEnabled = (shorthandExpansionEnabled != 0)
    AutoWordingEngine.shared.candidateSuggestionsEnabled = (candidateSuggestionsEnabled != 0)
}

public func OKEngineSyncConfig(
    _ language: Int,
    _ inputType: Int,
    _ checkSpelling: Int,
    _ useModernOrthography: Int,
    _ restoreIfWrongSpelling: Int,
    _ fixRecommendBrowser: Int,
    _ useSmartSwitchKey: Int,
    _ autoWordingEnabled: Int = 0,
    _ grammarRepairEnabled: Int = 0,
    _ shorthandExpansionEnabled: Int = 0,
    _ candidateSuggestionsEnabled: Int = 0
) {
    OKEngineSyncConfig(
        Int32(language),
        Int32(inputType),
        Int32(checkSpelling),
        Int32(useModernOrthography),
        Int32(restoreIfWrongSpelling),
        Int32(fixRecommendBrowser),
        Int32(useSmartSwitchKey),
        Int32(autoWordingEnabled),
        Int32(grammarRepairEnabled),
        Int32(shorthandExpansionEnabled),
        Int32(candidateSuggestionsEnabled)
    )
}

public func OKEngineHandleKeyEvent(
    _ keyCode: UInt16,
    _ capsStatus: UInt8,
    _ otherControlKey: Bool
) -> OKHookSnapshot {
    VietnameseEngineState.shared.handleKeyEvent(
        keyCode: keyCode,
        capsStatus: capsStatus,
        otherControlKey: otherControlKey
    )
}

public func OKEngineResetSession() {
    VietnameseEngineState.shared.resetSession()
}

public func OKEngineKeyCodeToChar(_ keyCodeWithCaps: UInt32) -> UInt16 {
    keyCodeToCharacter(keyCodeWithCaps)
}

public func OKInitSmartSwitchKey(_ data: UnsafePointer<UInt8>?, _ size: Int32) {
    VietnameseEngineState.shared.initSmartSwitchKey(data: data, size: size)
}

public func OKGetAppInputMethodStatus(_ bundleId: String, _ currentInputMethod: Int32) -> Int32 {
    VietnameseEngineState.shared.getAppInputMethodStatus(bundleId: bundleId, currentInputMethod: currentInputMethod)
}

public func OKSetAppInputMethodStatus(_ bundleId: String, _ language: Int32) {
    VietnameseEngineState.shared.setAppInputMethodStatus(bundleId: bundleId, language: language)
}

public func OKGetSmartSwitchKeySaveData(_ outBuffer: UnsafeMutablePointer<UInt8>?, _ maxBufferSize: Int32) -> Int32 {
    VietnameseEngineState.shared.getSmartSwitchKeySaveData(outBuffer: outBuffer, maxBufferSize: maxBufferSize)
}

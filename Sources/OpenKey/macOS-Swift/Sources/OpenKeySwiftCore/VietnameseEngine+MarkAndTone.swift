//
//  VietnameseEngine+MarkAndTone.swift
//  OpenKeySwiftCore
//
//  Converted to 100% Pure Swift 6 by Antigravity from the original C++ OpenKey engine:
//  Created by Mai Vũ Tuyên on 1/18/19.
//  Copyright © 2019 Mai Vũ Tuyên. All rights reserved.
//  Licensed under GNU General Public License v3.0.
//

import Foundation

// MARK: - Diacritic & Tone Mark Processing Extension (REQ-008, REQ-009, ADR-008)

extension VietnameseEngineState {
    
    func getCharacterCode(_ data: UInt32) -> UInt32 {
        let capsElem: Int = data.isCaps ? 0 : 1
        var key = UInt32(data.baseKey)
        
        if (data & MARK_MASK) != 0 {
            let markOffsets: [UInt32: Int] = [MARK1_MASK: 0, MARK2_MASK: 2, MARK3_MASK: 4, MARK4_MASK: 6, MARK5_MASK: 8]
            var markElem = (markOffsets[data & MARK_MASK] ?? -2) + capsElem
            let base = data.baseKey
            if (base == KEY_A || base == KEY_O || base == KEY_U || base == KEY_E) && !data.hasToneMark { markElem += 4 }
            if data.hasCircumflexOrStroke { key |= TONE_MASK }
            else if data.hasHornOrBreve { key |= TONEW_MASK }
            guard let table = _codeTable[key], markElem >= 0 && markElem < table.count else { return data }
            return UInt32(table[markElem]) | CHAR_CODE_MASK
        } else {
            guard let table = _codeTable[key] else { return data }
            if data.hasCircumflexOrStroke {
                guard capsElem < table.count else { return data }
                return UInt32(table[capsElem]) | CHAR_CODE_MASK
            } else if data.hasHornOrBreve {
                guard (capsElem + 2) < table.count else { return data }
                return UInt32(table[capsElem + 2]) | CHAR_CODE_MASK
            }
            return data
        }
    }
    
    func removeMark() {
        hookOutput.code = HookCodeState.doNothing
        guard index > 0 else { return }
        findAndCalculateVowel()
        let vsi = Int(vowelStartIndex), vei = Int(vowelEndIndex)
        isChanged = false
        hookOutput.code = HookCodeState.willProcess
        hookOutput.backspaceCount = 0
        
        for ii in stride(from: Int(index) - 1, through: 0, by: -1) {
            hookOutput.backspaceCount += 1
            if (typingWord[ii] & MARK_MASK) != 0 { typingWord[ii] &= ~MARK_MASK; isChanged = true }
            if vsi <= vei && ii >= vsi && ii <= vei && typingWord[ii].isAutoTone {
                typingWord[ii] &= ~(TONE_MASK | TONEW_MASK | AUTO_TONE_MASK)
                isChanged = true
            }
            hookOutput.charData[Int(index) - 1 - ii] = GET(typingWord[ii])
        }
        hookOutput.newCharCount = hookOutput.backspaceCount
        if !isChanged { hookOutput.code = HookCodeState.doNothing }
    }
    
    func handleModernMark() {
        vowelWillSetMark = vowelEndIndex
        let vsi = Int(vowelStartIndex), vei = Int(vowelEndIndex)
        let c0 = CHR(vsi)
        let c1 = vsi + 1 <= vei ? CHR(vsi + 1) : KEY_EMPTY
        let c2 = vsi + 2 <= vei ? CHR(vsi + 2) : KEY_EMPTY
        
        if vowelCount == 3 && ((c0 == KEY_O && c1 == KEY_A && c2 == KEY_I) || (c0 == KEY_U && c1 == KEY_Y && c2 == KEY_U) || (c0 == KEY_O && c1 == KEY_E && c2 == KEY_O) || (c0 == KEY_U && c1 == KEY_Y && c2 == KEY_A)) {
            vowelWillSetMark = UInt8(vsi + 1)
        } else if (c0 == KEY_O && c1 == KEY_I) || (c0 == KEY_A && c1 == KEY_I) || (c0 == KEY_U && c1 == KEY_I) {
            vowelWillSetMark = vowelStartIndex
        } else if vei > 0 && CHR(vei - 1) == KEY_A && CHR(vei) == KEY_Y {
            vowelWillSetMark = UInt8(vei - 1)
        } else if c0 == KEY_U && c1 == KEY_O {
            vowelWillSetMark = UInt8(vsi + 1)
        } else if c1 == KEY_O || c1 == KEY_U {
            vowelWillSetMark = UInt8(vei - 1)
        } else if c0 == KEY_O || c0 == KEY_U {
            vowelWillSetMark = vowelEndIndex
        }
        
        let isRule3_1: Bool = {
            guard vsi + 1 <= vei else { return false }
            let w1 = typingWord[vsi + 1]
            if (c0 == KEY_I || c0 == KEY_Y || c0 == KEY_U) && c1 == (c0 == KEY_U ? KEY_O : KEY_E) && w1.hasCircumflexOrStroke { return true }
            return c0 == KEY_U && typingWord[vsi].hasHornOrBreve && c1 == KEY_O && w1.hasHornOrBreve
        }()
        
        if isRule3_1 {
            let ch2 = vsi + 2 < Int(index) ? CHR(vsi + 2) : KEY_EMPTY
            let ch3 = vsi + 3 < Int(index) ? CHR(vsi + 3) : KEY_EMPTY
            let isEndMatch = [KEY_P, KEY_T, KEY_M, KEY_N, KEY_O, KEY_U, KEY_I, KEY_C].contains(ch2) || (ch2 == KEY_C && ch3 == KEY_H) || (ch2 == KEY_N && (ch3 == KEY_H || ch3 == KEY_G))
            vowelWillSetMark = (vsi + 2 < Int(index) && isEndMatch) ? UInt8(vsi + 1) : vowelStartIndex
        } else if (c0 == KEY_I && c1 == KEY_A) || (c0 == KEY_Y && c1 == KEY_A) || (c0 == KEY_U && c1 == KEY_A) || (c0 == KEY_U && (typingWord[vsi].hasHornOrBreve || typingWord[vsi + 1].hasHornOrBreve) && c1 == KEY_U) {
            vowelWillSetMark = vowelStartIndex
        }
        
        if vowelCount == 2 && vsi + 1 <= vei {
            if c0 == KEY_I && (c1 == KEY_A || c1 == KEY_U || c1 == KEY_O) {
                vowelWillSetMark = (vsi == 0 || CHR(vsi - 1) != KEY_G) ? vowelStartIndex : UInt8(vsi + 1)
            } else if c0 == KEY_U && c1 == KEY_A {
                vowelWillSetMark = (vsi != 0 && CHR(vsi - 1) == KEY_Q) ? UInt8(vsi + 1) : ((vei + 1 >= Int(index) || !canHasEndConsonant()) ? vowelStartIndex : vowelEndIndex)
            } else if c0 == KEY_O && c1 == KEY_O {
                vowelWillSetMark = vowelEndIndex
            }
        }
    }
    
    func handleOldMark() {
        vowelWillSetMark = (vowelCount == 0 && CHR(Int(vowelEndIndex)) == KEY_I) ? vowelEndIndex : vowelStartIndex
        let vsi = Int(vowelStartIndex), vei = Int(vowelEndIndex)
        if vowelCount == 3 || (vei + 1 < Int(index) && isConsonant(CHR(vei + 1)) && canHasEndConsonant()) {
            vowelWillSetMark = UInt8(vsi + 1)
        }
        for ii in vsi...vei {
            if (CHR(ii) == KEY_E && typingWord[ii].hasCircumflexOrStroke) ||
               (CHR(ii) == KEY_O && typingWord[ii].hasHornOrBreve) {
                vowelWillSetMark = UInt8(ii)
                break
            }
        }
    }
    
    func insertMark(markMask: UInt32, canModifyFlag: Bool = true) {
        if canModifyFlag {
            repairPhonotacticClusterIfNeeded(isInsertingMark: true)
            hookOutput.code = HookCodeState.willProcess
            hookOutput.backspaceCount = 0
            hookOutput.newCharCount = 0
        }
        vowelCount = 0
        findAndCalculateVowel()
        vowelWillSetMark = (vowelCount == 1) ? vowelEndIndex : 0
        if vowelCount > 1 {
            if vUseModernOrthography == 0 { handleOldMark() } else { handleModernMark() }
            if typingWord[Int(vowelEndIndex)].hasToneMark { vowelWillSetMark = vowelEndIndex }
        }
        let vsi = Int(vowelStartIndex), vwsm = Int(vowelWillSetMark)
        var kk = Int(index) - 1 - vsi
        let hasSameMark = (typingWord[vwsm] & markMask) != 0
        typingWord[vwsm] &= ~MARK_MASK
        if !hasSameMark { typingWord[vwsm] |= markMask }
        for ii in vsi..<Int(index) {
            if ii != vwsm { typingWord[ii] &= ~MARK_MASK }
            if hasSameMark && typingWord[ii].isAutoTone { typingWord[ii] &= ~(TONE_MASK | TONEW_MASK | AUTO_TONE_MASK) }
            if canModifyFlag && kk >= 0 {
                hookOutput.charData[kk] = GET(typingWord[ii])
                kk -= 1
            }
        }
        if canModifyFlag {
            hookOutput.code = hasSameMark ? HookCodeState.restore : HookCodeState.willProcess
            tempDisableKey = hasSameMark
            hookOutput.backspaceCount = UInt8(Int(index) - vsi)
            hookOutput.newCharCount = hookOutput.backspaceCount
        }
    }
    
    func insertD(data: UInt16, caps: Bool) {
        hookOutput.code = HookCodeState.willProcess; hookOutput.backspaceCount = 0
        guard index > 0 else { return }
        for ii in stride(from: Int(index) - 1, through: 0, by: -1) {
            hookOutput.backspaceCount += 1
            if CHR(ii) == KEY_D {
                if typingWord[ii].hasCircumflexOrStroke {
                    hookOutput.code = HookCodeState.restore; typingWord[ii] &= ~TONE_MASK; tempDisableKey = true
                } else {
                    typingWord[ii] |= TONE_MASK
                }
                hookOutput.charData[Int(index) - 1 - ii] = GET(typingWord[ii])
                break
            }
            hookOutput.charData[Int(index) - 1 - ii] = GET(typingWord[ii])
        }
        hookOutput.newCharCount = hookOutput.backspaceCount
    }
    
    func insertAOE(data: UInt16, caps: Bool) {
        findAndCalculateVowel()
        let vsi = Int(vowelStartIndex), vei = Int(vowelEndIndex)
        if vsi <= vei { for ii in vsi...vei { typingWord[ii] &= ~TONEW_MASK } }
        hookOutput.code = HookCodeState.willProcess; hookOutput.backspaceCount = 0
        guard index > 0 else { return }
        
        for ii in stride(from: Int(index) - 1, through: 0, by: -1) {
            hookOutput.backspaceCount += 1
            if CHR(ii) == data {
                if typingWord[ii].hasCircumflexOrStroke {
                    if typingWord[ii].isAutoTone {
                        typingWord[ii] &= ~AUTO_TONE_MASK
                    } else {
                        hookOutput.code = HookCodeState.restore; typingWord[ii] &= ~TONE_MASK
                        if data != KEY_O { tempDisableKey = true }
                    }
                } else {
                    typingWord[ii] |= TONE_MASK
                    if !isKeyD(data) { typingWord[ii] &= ~TONEW_MASK }
                }
                hookOutput.charData[Int(index) - 1 - ii] = GET(typingWord[ii])
                break
            }
            hookOutput.charData[Int(index) - 1 - ii] = GET(typingWord[ii])
        }
        hookOutput.newCharCount = hookOutput.backspaceCount
    }
    
    func insertW(data: UInt16, caps: Bool) {
        isRestoredW = false
        findAndCalculateVowel()
        let vsi = Int(vowelStartIndex), vei = Int(vowelEndIndex)
        if vsi <= vei {
            for ii in vsi...vei { typingWord[ii] &= ~TONE_MASK }
        }
        
        if vowelCount > 1 {
            hookOutput.backspaceCount = UInt8(Int(index) - vsi)
            hookOutput.newCharCount = hookOutput.backspaceCount
            
            let hasW0 = typingWord[vsi].hasHornOrBreve
            let hasW1 = vsi + 1 < maxBuff && typingWord[vsi + 1].hasHornOrBreve
            let ch1 = vsi + 1 < maxBuff ? CHR(vsi + 1) : 0
            
            if (hasW0 && hasW1) || (hasW0 && (ch1 == KEY_I || ch1 == KEY_A)) {
                let autoTone = typingWord[vsi].isAutoTone || (vsi + 1 < maxBuff && typingWord[vsi + 1].isAutoTone)
                hookOutput.code = autoTone ? HookCodeState.willProcess : HookCodeState.restore
                for ii in vsi..<Int(index) {
                    if autoTone { typingWord[ii] &= ~AUTO_TONE_MASK }
                    else { typingWord[ii] &= ~TONEW_MASK }
                    let mask = autoTone ? ~UInt32(0) : ~STANDALONE_MASK
                    hookOutput.charData[Int(index) - 1 - ii] = GET(typingWord[ii]) & mask
                }
                if !autoTone { isRestoredW = true; tempDisableKey = true }
            } else {
                hookOutput.code = HookCodeState.willProcess
                let ch0 = CHR(vsi)
                if ch0 == KEY_U && ch1 == KEY_O {
                    let hasTh = vsi >= 2 && CHR(vsi - 2) == KEY_T && CHR(vsi - 1) == KEY_H
                    let hasQ = vsi >= 1 && CHR(vsi - 1) == KEY_Q
                    if hasTh {
                        typingWord[vsi + 1] |= TONEW_MASK
                        if vsi + 2 < Int(index) && CHR(vsi + 2) == KEY_N { typingWord[vsi] |= TONEW_MASK }
                    } else if hasQ {
                        typingWord[vsi + 1] |= TONEW_MASK
                    } else {
                        typingWord[vsi] |= TONEW_MASK; typingWord[vsi + 1] |= TONEW_MASK
                    }
                } else if (ch0 == KEY_U && (ch1 == KEY_A || ch1 == KEY_I || ch1 == KEY_U)) || (ch0 == KEY_O && ch1 == KEY_I) {
                    typingWord[vsi] |= TONEW_MASK
                } else if (ch0 == KEY_I && ch1 == KEY_O) || (ch0 == KEY_O && ch1 == KEY_A) {
                    typingWord[vsi + 1] |= TONEW_MASK
                } else {
                    tempDisableKey = true; isChanged = false; hookOutput.code = HookCodeState.doNothing
                }
                for ii in vsi..<Int(index) { hookOutput.charData[Int(index) - 1 - ii] = GET(typingWord[ii]) }
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
            if ch == KEY_A || ch == KEY_U || ch == KEY_O {
                if typingWord[ii].hasHornOrBreve {
                    if typingWord[ii].isAutoTone {
                        typingWord[ii] &= ~AUTO_TONE_MASK
                        hookOutput.code = HookCodeState.willProcess
                    } else if typingWord[ii].isStandaloneW {
                        hookOutput.code = (ch == KEY_U) ? HookCodeState.willProcess : HookCodeState.restore
                        typingWord[ii] = UInt32(ch == KEY_U ? KEY_W : KEY_O) | (typingWord[ii].isCaps ? CAPS_MASK : 0)
                        if ch == KEY_O { isRestoredW = true }
                    } else {
                        hookOutput.code = HookCodeState.restore
                        typingWord[ii] &= ~TONEW_MASK
                        isRestoredW = true
                    }
                    tempDisableKey = true
                } else {
                    typingWord[ii] = (typingWord[ii] | TONEW_MASK) & ~TONE_MASK
                }
                hookOutput.charData[Int(index) - 1 - ii] = GET(typingWord[ii])
                break
            } else {
                hookOutput.charData[Int(index) - 1 - ii] = GET(typingWord[ii])
            }
        }
        hookOutput.newCharCount = hookOutput.backspaceCount
    }
    
    func reverseLastStandaloneChar(keyCode: UInt32, caps: Bool) {
        hookOutput.code = HookCodeState.willProcess
        hookOutput.backspaceCount = 0
        hookOutput.newCharCount = 1
        hookOutput.extCode = 4
        typingWord[Int(index) - 1] = keyCode | TONEW_MASK | STANDALONE_MASK | (caps ? CAPS_MASK : 0)
        hookOutput.charData[0] = GET(typingWord[Int(index) - 1])
    }
    
    func checkForStandaloneChar(data: UInt16, caps: Bool, keyWillReverse: UInt32) {
        if index > 0 && CHR(Int(index) - 1) == UInt16(keyWillReverse) && typingWord[Int(index) - 1].hasHornOrBreve {
            hookOutput.code = HookCodeState.willProcess
            hookOutput.backspaceCount = 1; hookOutput.newCharCount = 1
            typingWord[Int(index) - 1] = UInt32(data) | (caps ? CAPS_MASK : 0)
            hookOutput.charData[0] = GET(typingWord[Int(index) - 1])
            return
        }
        if index > 0 && CHR(Int(index) - 1) == KEY_U && keyWillReverse == UInt32(KEY_O) {
            insertKey(keyCode: UInt16(keyWillReverse), caps: caps)
            reverseLastStandaloneChar(keyCode: keyWillReverse, caps: caps)
            return
        }
        let shouldReverse: Bool = {
            if index == 0 { return true }
            if index == 1 { return !_standaloneWbad.contains(CHR(0)) }
            if index == 2 { return _doubleWAllowed.contains(where: { $0[0] == CHR(0) && $0[1] == CHR(1) }) }
            return false
        }()
        if shouldReverse {
            insertKey(keyCode: data, caps: caps, isCheckSpellingFlag: false)
            reverseLastStandaloneChar(keyCode: keyWillReverse, caps: caps)
        } else {
            insertKey(keyCode: data, caps: caps)
        }
    }
    
    func handleMainKey(data: UInt16, caps: Bool) {
        if isKeyZ(data) {
            removeMark()
            if !isChanged { insertKey(keyCode: data, caps: caps) }
            return
        }
        if data == KEY_LEFT_BRACKET { checkForStandaloneChar(data: data, caps: caps, keyWillReverse: UInt32(KEY_O)); return }
        if data == KEY_RIGHT_BRACKET { checkForStandaloneChar(data: data, caps: caps, keyWillReverse: UInt32(KEY_U)); return }
        
        if isKeyD(data) {
            isCorrect = false; isChanged = false
            for i in 0..<_consonantD.count where Int(index) >= _consonantD[i].count {
                isCorrect = true
                checkCorrectVowel(charset: _consonantD, i: i, markKey: data)
                if !isCorrect && index >= 2 && CHR(Int(index) - 1) == KEY_D && isConsonant(CHR(Int(index) - 2)) { isCorrect = true }
                if isCorrect { isChanged = true; insertD(data: data, caps: caps); break }
            }
            if !isChanged { insertKey(keyCode: data, caps: caps) }
            return
        }
        
        if isMarkKey(data) {
            for (_, charset) in _vowelForMark {
                isCorrect = false; isChanged = false
                for l in 0..<charset.count where Int(index) >= charset[l].count {
                    isCorrect = true
                    checkCorrectVowel(charset: charset, i: l, markKey: data)
                    if isCorrect {
                        isChanged = true
                        let mask: UInt32 = isKeyS(data) ? MARK1_MASK : (isKeyF(data) ? MARK2_MASK : (isKeyR(data) ? MARK3_MASK : (isKeyX(data) ? MARK4_MASK : MARK5_MASK)))
                        insertMark(markMask: mask)
                        break
                    }
                }
                if isCorrect { break }
            }
            if !isChanged { insertKey(keyCode: data, caps: caps) }
            return
        }
        
        if vInputType == 1 {
            for i in stride(from: Int(index) - 1, through: 0, by: -1) {
                let ch = CHR(i)
                if ch == KEY_O || ch == KEY_A || ch == KEY_E { vowelEndIndex = UInt8(i); break }
            }
        }
        
        keyForAEO = (vInputType != 1) ? data : ((data == KEY_7 || data == KEY_8) ? KEY_W : ((data == KEY_6) ? CHR(Int(vowelEndIndex)) : data))
        
        if let charset = _vowel[keyForAEO] {
            isCorrect = false; isChanged = false
            for i in 0..<charset.count where Int(index) >= charset[i].count {
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
                                if ch == KEY_O || ch == KEY_U || ch == KEY_A || ch == KEY_E { vowelEndIndex = UInt8(j); break }
                            }
                            let vei = Int(vowelEndIndex), chVei = CHR(vei)
                            if (data == KEY_7 && chVei == KEY_A && (vei - 1 >= 0 ? CHR(vei - 1) != KEY_U : true)) ||
                               (data == KEY_8 && (chVei == KEY_O || chVei == KEY_U)) { break }
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
}

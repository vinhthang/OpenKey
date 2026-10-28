//
//  VietnameseEngine+SpellingAndGrammar.swift
//  OpenKeySwiftCore
//
//  Converted to 100% Pure Swift 6 by Antigravity from the original C++ OpenKey engine:
//  Created by Mai Vũ Tuyên on 1/18/19.
//  Copyright © 2019 Mai Vũ Tuyên. All rights reserved.
//  Licensed under GNU General Public License v3.0.
//

import Foundation

// MARK: - Spelling & Grammar Validation Extension (REQ-008, REQ-009, ADR-008)

extension VietnameseEngineState {
    
    func checkSpelling(forceCheckVowel: Bool = false) {
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
                                    let actual = UInt32(CHR(targetIdx)) | typingWord[targetIdx].toneMark
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
    
    @discardableResult
    func repairPhonotacticClusterIfNeeded(isInsertingMark: Bool = false) -> Bool {
        guard let hook = phonotacticRepairHook else { return false }
        guard index >= 3 else { return false }
        
        findAndCalculateVowel(forGrammar: true)
        guard vowelCount >= 2 else { return false }
        
        return hook(
            &typingWord,
            index,
            vowelStartIndex,
            vowelEndIndex,
            vowelCount,
            isInsertingMark
        )
    }
    
    func checkGrammar(deltaBackSpace: Int) {
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
                        let mask1 = typingWord[i - 1].hasHornOrBreve
                        let mask2 = typingWord[i - 2].hasHornOrBreve
                        if mask1 != mask2 {
                            if !typingWord[i - 2].hasHornOrBreve { typingWord[i - 2] |= (TONEW_MASK | AUTO_TONE_MASK) }
                            if !typingWord[i - 1].hasHornOrBreve { typingWord[i - 1] |= (TONEW_MASK | AUTO_TONE_MASK) }
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
    
    func checkCorrectVowel(charset: [[UInt16]], i: Int, markKey: UInt16) {
        if index >= 2 && CHR(Int(index) - 1) == KEY_U && CHR(Int(index) - 2) == KEY_Q {
            isCorrect = false
            return
        }
        var k = Int(index) - 1
        for j in stride(from: charset[i].count - 1, through: 0, by: -1) {
            let ch = charset[i][j]
            if (ch & END_CONSONANT_MASK) != 0 {
                isCorrect = false
                return
            }
            if ch != CHR(k) {
                isCorrect = false
                return
            }
            k -= 1
            if k < 0 { break }
        }
        
        // limit mark for end consonant: "C", "T"
        if isCorrect && charset[i].count > 1 && (isKeyF(markKey) || isKeyX(markKey) || isKeyR(markKey)) {
            if charset[i][1] == KEY_C || charset[i][1] == KEY_T {
                isCorrect = false
            } else if charset[i].count > 2 && charset[i][2] == KEY_T {
                isCorrect = false
            }
        }
        
        if isCorrect && k >= 0 {
            if (k > 0 && CHR(k) == CHR(k - 1)) || (k + 1 < Int(index) && CHR(k) == CHR(k + 1)) {
                isCorrect = false
            }
        }
    }
    
    func findAndCalculateVowel(forGrammar: Bool = false) {
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
            vowelCount -= 1
        }
    }
    
    func canHasEndConsonant() -> Bool {
        guard let vo = _vowelCombine[CHR(Int(vowelStartIndex))] else { return false }
        for ii in 0..<vo.count {
            var kk = Int(vowelStartIndex)
            var iii = 1
            while iii < vo[ii].count {
                if kk > Int(vowelEndIndex) || ((UInt32(CHR(kk)) | typingWord[kk].toneMark) != vo[ii][iii]) {
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
    
    func checkRestoreIfWrongSpelling(handleCode: UInt8) -> Bool {
        guard index > 0 else { return false }
        for ii in 0..<Int(index) {
            if typingWord[ii].hasAnyDiacritic {
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
}

//
//  VietnameseEngine+KeyEventDispatcher.swift
//  OpenKeySwiftCore
//
//  Converted to 100% Pure Swift 6 by Antigravity from the original C++ OpenKey engine:
//  Created by Mai Vũ Tuyên on 1/18/19.
//  Copyright © 2019 Mai Vũ Tuyên. All rights reserved.
//  Licensed under GNU General Public License v3.0.
//

import Foundation

// MARK: - Event Dispatcher Extension (REQ-008, REQ-009, ADR-008)

extension VietnameseEngineState {
    
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
    }
    
    func handleSpaceKey() {
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
            if hookOutput.code == HookCodeState.doNothing || (hookOutput.extCode == 4 && hookOutput.backspaceCount == 0 && hookOutput.newCharCount == 1) {
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
    
    func buildOutputSnapshot(forKeyCode keyCode: UInt16) -> OKHookSnapshot {
        if hookOutput.code == HookCodeState.doNothing {
            return OKHookSnapshot(
                code: HookCodeState.doNothing,
                backspaceCount: 0,
                newCharCount: 0,
                extCode: hookOutput.extCode,
                shouldSendControlKey: false,
                utf16Chars: []
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
        
        return OKHookSnapshot(
            code: hookOutput.code,
            backspaceCount: hookOutput.backspaceCount,
            newCharCount: UInt8(chars.count),
            extCode: hookOutput.extCode,
            shouldSendControlKey: shouldSendControl,
            utf16Chars: chars
        )
    }
}

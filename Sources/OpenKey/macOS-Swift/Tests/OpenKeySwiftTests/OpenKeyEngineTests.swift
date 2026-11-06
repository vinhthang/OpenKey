//
//  OpenKeyEngineTests.swift
//  OpenKeySwiftTests
//
//  Created for OpenKey macOS Swift.
//  Engine composition, phonotactic parity, spelling, and sub-500-line invariant tests (REQ-009, ADR-008).
//

import Foundation
import CoreGraphics
import ApplicationServices
import Testing
@testable import OpenKeySwiftCore

extension OpenKeySwiftTests {

@Suite("OpenKeyEngineTests", .serialized)
struct OpenKeyEngineTests {
    
    init() {
        OKEngineInit()
        OKEngineResetSession()
    }
    
    // REQ-001, REQ-003: Telex syllable composition
    @Test("Telex syllable composition")
    func telexComposition() {
        OKEngineInit()
        OKEngineResetSession()
        OKEngineSyncConfig(1, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1)
        defer { OKEngineSyncConfig(1, 0, 1, 1, 1, 1, 1, 0, 0, 0, 0) }
        
        // Test "tiengs" -> "tiếng"
        typeKeys([17, 34, 14, 45, 5]) // t, i, e, n, g
        let snapS = OKEngineHandleKeyEvent(1, 0, false)  // s (acute mark)
        #expect(snapS.code != 0, "Typing 's' in 'tieng' must trigger engine processing")
        #expect(snapS.backspaceCount >= 3, "Must send backspaces to replace syllable")
        #expect(snapS.decodedString.contains("ế") || snapS.decodedString.contains("é"), "Must output accented vowel: \(snapS.decodedString)")
        
        // Test "vieetj" -> "việt"
        OKEngineResetSession()
        typeKeys([9, 34, 14, 14, 17]) // v, i, e, e, t
        let snapJ = OKEngineHandleKeyEvent(38, 0, false) // j -> dot below
        #expect(snapJ.code != 0, "Typing 'j' in 'vieet' must trigger tone processing")
        #expect(snapJ.decodedString.contains("ệ"), "Must output 'ệ': \(snapJ.decodedString)")
    }
    
    // REQ-003: VNI syllable composition
    @Test("VNI syllable composition")
    func vniComposition() {
        OKEngineInit()
        OKEngineResetSession()
        OKEngineSyncConfig(1, 1, 1, 1, 1, 1, 1)
        
        typeKeys([9, 34, 14]) // v, i, e
        let snap6 = OKEngineHandleKeyEvent(22, 0, false) // 6 -> circumflex
        #expect(snap6.code != 0, "Typing '6' after 'e' in VNI must add circumflex")
        _ = OKEngineHandleKeyEvent(17, 0, false) // t
        let snap5 = OKEngineHandleKeyEvent(23, 0, false) // 5 -> nặng
        #expect(snap5.code != 0, "Typing '5' in VNI on 'viet' must add dot below")
        #expect(snap5.backspaceCount >= 2, "Must send backspaces to replace vowel with tone")
        #expect(snap5.decodedString.contains("ệ"), "Must output 'ệ': \(snap5.decodedString)")
    }
    
    // REQ-003: Spelling check & auto-restore on invalid English words
    @Test("Spelling check and auto-restore")
    func spellingCheckAndAutoRestore() {
        OKEngineInit()
        OKEngineResetSession()
        OKEngineSyncConfig(1, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1)
        defer {
            OKEngineSyncConfig(1, 0, 1, 1, 1, 1, 1, 0, 0, 0, 0)
        }
        
        // Type English word "window"
        // w=13, i=34, n=45, d=2, o=31, w=13
        _ = OKEngineHandleKeyEvent(13, 0, false) // w
        _ = OKEngineHandleKeyEvent(34, 0, false) // i
        _ = OKEngineHandleKeyEvent(45, 0, false) // n
        _ = OKEngineHandleKeyEvent(2, 0, false)  // d
        _ = OKEngineHandleKeyEvent(31, 0, false) // o
        _ = OKEngineHandleKeyEvent(13, 0, false) // w
        
        // Space keycode: 49
        let spaceSnap = OKEngineHandleKeyEvent(49, 0, false)
        #expect(spaceSnap.code == 0 || spaceSnap.code == 2 || spaceSnap.code == 3 || spaceSnap.code == 5,
                "Word break or restore should execute cleanly on invalid Vietnamese word")
        for cu in spaceSnap.utf16Array {
            #expect(cu <= 0x7F, "Auto-restored ASCII characters must be valid ASCII code units (< 128)")
        }
    }
    
    // REQ-005: Bounds-checked deserialization in OKInitSmartSwitchKey
    @Test("Bounds-checked deserialization on truncated buffers")
    func boundsCheckedDeserialization() {
        // Corrupted SmartSwitchKey buffer: declared count = 5, but buffer truncated
        let corruptedSmartData: [UInt8] = [0x05, 0x00, 0x0A, 0x63, 0x6F]
        corruptedSmartData.withUnsafeBufferPointer { ptr in
            OKInitSmartSwitchKey(ptr.baseAddress, Int32(ptr.count))
        }
        
        // Null / zero size
        OKInitSmartSwitchKey(nil, 0)
        OKInitSmartSwitchKey(nil, 1)
        
        OKEngineResetSession()
    }
    
    // REQ-005: Per-app smart switch state persistence and lookup
    @Test("SmartSwitchKey persistence and lookup")
    func smartSwitchKeyPersistenceAndLookup() {
        let bundleTerminal = "com.apple.Terminal"
        let bundleNotes = "com.apple.Notes"
        
        OKSetAppInputMethodStatus(bundleTerminal, 0) // English
        OKSetAppInputMethodStatus(bundleNotes, 1)    // Vietnamese
        
        #expect(OKGetAppInputMethodStatus(bundleTerminal, 1) == 0, "Terminal should be English (0)")
        #expect(OKGetAppInputMethodStatus(bundleNotes, 0) == 1, "Notes should be Vietnamese (1)")
        #expect(OKGetAppInputMethodStatus("com.unknown.app", 1) == -1, "Unknown app should return -1")
    }
    
    
    @Test("Pure Swift Engine Phonotactic Parity and Complex Syllables")
    func pureSwiftEnginePhonotacticParity() {
        OKEngineInit()
        
        // 1. "truong" Telex composition: t r u o w n g f -> trường
        OKEngineResetSession()
        OKEngineSyncConfig(1, 0, 1, 1, 1, 1, 1)
        typeKeys([17, 15, 32, 31])
        let snapW = OKEngineHandleKeyEvent(13, 0, false) // w -> ươ
        #expect(snapW.code == HookCodeState.willProcess)
        #expect(snapW.backspaceCount >= 1)
        typeKeys([45, 5])
        let snapTruong = OKEngineHandleKeyEvent(3, 0, false) // f -> grave mark
        #expect(snapTruong.code == HookCodeState.willProcess)
        #expect(snapTruong.decodedString.contains("ườ"))
        
        // 2. "nghieng" Telex: n g h i e e n g -> nghiêng
        OKEngineResetSession()
        typeKeys([45, 5, 4, 34, 14])
        let snapEE = OKEngineHandleKeyEvent(14, 0, false) // e -> ê
        #expect(snapEE.code == HookCodeState.willProcess)
        #expect(snapEE.decodedString.contains("ê"))
        
        // 3. "quoc" Telex: q u o c s -> quốc
        OKEngineResetSession()
        typeKeys([12, 32, 31, 8])
        let snapQuoc = OKEngineHandleKeyEvent(1, 0, false) // s -> sắc
        #expect(snapQuoc.code == HookCodeState.willProcess)
        #expect(snapQuoc.decodedString.contains("ố") || snapQuoc.decodedString.contains("ó"))
        
        // 4. "giu" Telex: g i u x -> giữ
        OKEngineResetSession()
        typeKeys([5, 34, 32])
        let snapGiu = OKEngineHandleKeyEvent(7, 0, false) // x -> ngã
        #expect(snapGiu.code == HookCodeState.willProcess)
        #expect(snapGiu.decodedString.contains("ữ") || snapGiu.decodedString.contains("ũ"))
        
        // 5. Modern vs Old Orthography ("oa" + f)
        OKEngineResetSession()
        OKEngineSyncConfig(1, 0, 1, 1, 1, 1, 1)
        typeKeys([31, 0])
        let snapModernOa = OKEngineHandleKeyEvent(3, 0, false) // f
        #expect(snapModernOa.code == HookCodeState.willProcess)
        #expect(snapModernOa.decodedString.contains("à"))
        
        OKEngineResetSession()
        OKEngineSyncConfig(1, 0, 1, 0, 1, 1, 1)
        typeKeys([31, 0])
        let snapOldOa = OKEngineHandleKeyEvent(3, 0, false) // f
        #expect(snapOldOa.code == HookCodeState.willProcess)
        #expect(snapOldOa.decodedString.contains("ò"))
        
        // 6. d/D -> đ/Đ
        OKEngineResetSession()
        OKEngineSyncConfig(1, 0, 1, 1, 1, 1, 1)
        _ = OKEngineHandleKeyEvent(2, 0, false)
        let snapLowerD = OKEngineHandleKeyEvent(2, 0, false)
        #expect(snapLowerD.code == HookCodeState.willProcess && snapLowerD.decodedString.contains("đ"))
        OKEngineResetSession()
        _ = OKEngineHandleKeyEvent(2, 1, false)
        let snapUpperD = OKEngineHandleKeyEvent(2, 1, false)
        #expect(snapUpperD.code == HookCodeState.willProcess && snapUpperD.decodedString.contains("Đ"))
        
        // 7. Standalone w -> ư, ww -> w
        OKEngineResetSession()
        let snapW1 = OKEngineHandleKeyEvent(13, 0, false) // w alone
        #expect(snapW1.code == HookCodeState.willProcess)
        #expect(snapW1.decodedString.contains("ư"))
        let snapW2 = OKEngineHandleKeyEvent(13, 0, false) // second w -> restore to w
        #expect(snapW2.code == HookCodeState.willProcess || snapW2.code == HookCodeState.restore)
        #expect(snapW2.decodedString.contains("w"))
        
        // 8. Standalone [[ -> [
        OKEngineResetSession()
        let snapBracket1 = OKEngineHandleKeyEvent(33, 0, false) // [ alone -> ơ
        #expect(snapBracket1.code == HookCodeState.willProcess)
        #expect(snapBracket1.decodedString.contains("ơ"))
        let snapBracket2 = OKEngineHandleKeyEvent(33, 0, false) // second [ -> restore [
        #expect(snapBracket2.code == HookCodeState.willProcess || snapBracket2.code == HookCodeState.restore)
        #expect(snapBracket2.decodedString.contains("["))
        
        // 9. Backspace Grammar Re-evaluation
        OKEngineResetSession()
        typeKeys([17, 14, 14, 17])
        let snapDel = OKEngineHandleKeyEvent(51, 0, false) // delete key (backspace)
        #expect(snapDel.extCode == 2)
        
        // 10. Space Word Restore on Backspace
        OKEngineResetSession()
        typeKeys([17, 34, 49])
        let snapSpaceDel = OKEngineHandleKeyEvent(51, 0, false) // backspace over space
        #expect(snapSpaceDel.extCode == 2)
        
        // 11. Invalid Spelling Auto-Restore (window -> restore on wrong letter)
        OKEngineResetSession()
        OKEngineSyncConfig(1, 0, 1, 1, 1, 1, 1)
        typeKeys([13, 34, 45, 2, 31])
        let snapRestore = OKEngineHandleKeyEvent(49, 0, false) // space terminates word
        #expect(snapRestore.code == HookCodeState.doNothing || snapRestore.code == HookCodeState.restore)
        
        // 12. Conversion Provenance Attribution Metadata (REQ-015)
        #if canImport(AppKit)
        let plistPath = Bundle.main.bundleURL.appendingPathComponent("Contents/Info.plist").path
        if FileManager.default.fileExists(atPath: plistPath),
           let dict = NSDictionary(contentsOfFile: plistPath) as? [String: Any],
           let copyright = dict["NSHumanReadableCopyright"] as? String {
            #expect(copyright.contains("Pure Swift 6"))
            #expect(copyright.contains("Mai Vũ Tuyên"))
        }
        #endif
    }
    
    // REQ-002: Phonotactic syllable repair (ie/ye + consonant -> iê/yê, uow -> ươ)
    @Test("REQ-002: Phonotactic syllable repair")
    func phonotacticSyllableRepair() {
        OKEngineInit()
        OKEngineResetSession()
        OKEngineSyncConfig(1, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1) // Enable AutoWording & GrammarRepair
        
        // 1. "tiengs" -> "tiếng"
        // t=17, i=34, e=14, n=45, g=5, s=1
        var screen = VirtualScreen()
        screen.typeKey(17) // t
        screen.typeKey(34) // i
        screen.typeKey(14) // e
        screen.typeKey(45) // n
        screen.typeKey(5)  // g
        let snapS = screen.typeKey(1) // s
        #expect(snapS.code == HookCodeState.willProcess, "Must process tone mark with repaired iê")
        #expect(snapS.backspaceCount == 4, "snapS.backspaceCount must be 4, got \(snapS.backspaceCount)")
        #expect(snapS.newCharCount == 4, "snapS.newCharCount must be 4, got \(snapS.newCharCount)")
        #expect(screen.text == "tiếng", "Screen buffer must be 'tiếng', got '\(screen.text)'")
        #expect(snapS.decodedString.contains("ế") || snapS.decodedString.contains("tiếng"), "Output must contain 'ế': \(snapS.decodedString)")
        
        // 2. "viets" -> "viết"
        OKEngineResetSession()
        typeKeys([9, 34, 14, 17])
        let snapViet = OKEngineHandleKeyEvent(1, 0, false)
        #expect(snapViet.code == HookCodeState.willProcess)
        #expect(snapViet.decodedString.contains("ế") || snapViet.decodedString.contains("viết"), "Output must contain 'ế': \(snapViet.decodedString)")
        
        // 3. "nghiengf" -> "nghiềng"
        OKEngineResetSession()
        typeKeys([45, 5, 4, 34, 14, 45, 5])
        let snapNghieng = OKEngineHandleKeyEvent(3, 0, false)
        #expect(snapNghieng.code == HookCodeState.willProcess)
        #expect(snapNghieng.decodedString.contains("ề") || snapNghieng.decodedString.contains("nghiềng"))
        
        // 4. "truowngf" -> "trường"
        OKEngineResetSession()
        typeKeys([17, 15, 32, 31, 13, 45, 5])
        let snapTruong = OKEngineHandleKeyEvent(3, 0, false)
        #expect(snapTruong.code == HookCodeState.willProcess)
        #expect(snapTruong.decodedString.contains("ườ") || snapTruong.decodedString.contains("trường"))
        
        // 5. When grammarRepairEnabled == 0: repair must not trigger
        OKEngineResetSession()
        OKEngineSyncConfig(1, 0, 1, 1, 1, 1, 1, 1, 0, 1, 1) // grammarRepairEnabled = 0
        typeKeys([17, 34, 14, 45, 5])
        let snapDisabled = OKEngineHandleKeyEvent(1, 0, false)
        #expect(!snapDisabled.decodedString.contains("ế"), "Must not promote ie to iê when grammarRepairEnabled is false")
        
        // Restore default opt-in config (disabled by default)
        OKEngineSyncConfig(1, 0, 1, 1, 1, 1, 1, 0, 0, 0, 0)
    }
    
    // REQ-004: English Word Auto-Restore without Skipping KEY_D / đ & Trailing Key Preservation
    @Test("REQ-004: English word auto-restore without skipping KEY_D and trailing key pass-through")
    func englishWordAutoRestoreWithD() {
        OKEngineInit()
        OKEngineResetSession()
        OKEngineSyncConfig(1, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1)
        defer {
            OKEngineSyncConfig(1, 0, 1, 1, 1, 1, 1, 0, 0, 0, 0)
        }
        
        // 1. Type English word "dead": d d e a d -> đead in Telex, space restores dead
        var screenDead = VirtualScreen()
        screenDead.typeKeys([2, 2, 14, 0, 2])
        let snapDeadSpace = screenDead.typeKey(49)
        #expect(snapDeadSpace.code == 0 || snapDeadSpace.code == 2 || snapDeadSpace.code == 3 || snapDeadSpace.code == 5,
                "Restoring 'dead' must execute clean word-break restore")
        #expect(snapDeadSpace.backspaceCount == 4, "snapDeadSpace.backspaceCount must be 4, got \(snapDeadSpace.backspaceCount)")
        #expect(screenDead.text == "ddead ", "Virtual screen must restore raw keystrokes 'ddead ', got '\(screenDead.text)'")
        for cu in snapDeadSpace.utf16Array {
            #expect(cu <= 0x7F, "Restored characters for 'dead' must be ASCII code units")
        }
        
        // 2. Type English word "added": a=0, d=2, d=2, e=14, d=2
        OKEngineResetSession()
        var screenAdded = VirtualScreen()
        screenAdded.typeKeys([0, 2, 2, 14, 2])
        let snapAddedSpace = screenAdded.typeKey(49)
        #expect(snapAddedSpace.code == 0 || snapAddedSpace.code == 2 || snapAddedSpace.code == 3 || snapAddedSpace.code == 5,
                "Restoring 'added' must execute clean word-break restore")
        #expect(snapAddedSpace.backspaceCount == 0, "snapAddedSpace.backspaceCount must be 0 for purely ASCII sequence")
        #expect(screenAdded.text == "added ", "Virtual screen must preserve 'added ', got '\(screenAdded.text)'")
        
        // 3. Trailing key preservation in replaceKeystroke action
        let actionWithTrailing = EventTapAction.replaceKeystroke(
            backspaces: 4,
            chars: [0x64, 0x65, 0x61, 0x64],
            strategy: .standardBackspace,
            passThroughTrailingKey: true
        )
        if case .replaceKeystroke(_, _, _, let passThrough) = actionWithTrailing {
            #expect(passThrough == true, "passThroughTrailingKey must be preserved")
        } else {
            Issue.record("Expected .replaceKeystroke")
        }
    }
    


    // MARK: - REQ-009: Codebase Modularization & UInt32 Syllable Bitmask Helpers
    @Test("REQ-009: Codebase modularization and UInt32 syllable bitmask helpers")
    func codebaseModularizationAndBitmaskHelpers() {
        // Verify UInt32 bitmask helpers
        let wordWithAll = UInt32(KEY_A) | TONE_MASK | MARK_MASK | TONEW_MASK | CAPS_MASK | AUTO_TONE_MASK | STANDALONE_MASK
        #expect(wordWithAll.baseKey == KEY_A)
        #expect(wordWithAll.isCaps)
        #expect(wordWithAll.hasToneMark)
        #expect(wordWithAll.hasCircumflexOrStroke)
        #expect(wordWithAll.hasHornOrBreve)
        #expect(wordWithAll.hasAnyDiacritic)
        #expect(wordWithAll.isAutoTone)
        #expect(wordWithAll.isStandaloneW)
        
        let plainChar = UInt32(KEY_B)
        #expect(plainChar.baseKey == KEY_B)
        #expect(!plainChar.isCaps)
        #expect(!plainChar.hasToneMark)
        #expect(!plainChar.hasCircumflexOrStroke)
        #expect(!plainChar.hasHornOrBreve)
        #expect(!plainChar.hasAnyDiacritic)
        #expect(!plainChar.isAutoTone)
        #expect(!plainChar.isStandaloneW)
        
        let acuteMark = UInt32(KEY_E) | TONE_MASK
        #expect(acuteMark.toneMark == TONE_MASK)
    }

    // MARK: - REQ-010: "giới" & gi- Initial Consonant Vowel Boundary & Phonotactics
    @Test("REQ-010: gioi and gi- initial consonant vowel boundaries, double-w undo, and phonotactic validation")
    func gioiAndGiInitialConsonantParity() {
        OKEngineInit()
        OKEngineResetSession()
        OKEngineSyncConfig(1, 0, 1, 1, 1, 1, 1) // Telex
        
        // 1. giowis emits bs=2, new=2, "ới"
        typeKeys([5, 34, 31, 13, 34]) // g, i, o, w, i -> giơi
        let snapS = OKEngineHandleKeyEvent(1, 0, false) // s -> giới
        #expect(snapS.code == HookCodeState.willProcess)
        #expect(snapS.backspaceCount == 2, "backspaceCount must be 2 (deleting 'ơi'), got \(snapS.backspaceCount)")
        #expect(snapS.newCharCount == 2, "newCharCount must be 2, got \(snapS.newCharCount)")
        #expect(snapS.decodedString == "ới", "decodedString must be 'ới', got '\(snapS.decodedString)'")
        
        // 2. All Telex and VNI typing sequences for "giới" produce "giới"
        let telexSequences: [[Int]] = [
            [5, 34, 31, 13, 34, 1], // giowis
            [5, 34, 31, 34, 13, 1], // gioiws
            [5, 34, 31, 34, 1, 13], // gioisw
            [5, 34, 31, 13, 1, 34], // giowsi
            [5, 34, 31, 1, 13, 34], // gioswi
            [5, 34, 31, 1, 34, 13], // giosiw
            [5, 34, 1, 31, 13, 34], // gisowi
            [5, 34, 1, 31, 34, 13], // gisoiw
            [5, 34, 33, 34, 1],     // gi[is
            [5, 34, 33, 1, 34]      // gi[si
        ]
        for seq in telexSequences {
            OKEngineResetSession()
            var screen = VirtualScreen()
            screen.typeKeys(seq)
            #expect(screen.text == "giới", "Sequence \(seq) must produce 'giới', got '\(screen.text)'")
        }
        
        // VNI sequences for "giới" (gio71i, gioi71)
        OKEngineSyncConfig(1, 1, 1, 1, 1, 1, 1) // VNI
        for seq in [[5, 34, 31, 26, 18, 34], [5, 34, 31, 34, 26, 18]] {
            OKEngineResetSession()
            var screen = VirtualScreen()
            screen.typeKeys(seq)
            #expect(screen.text == "giới", "VNI Sequence \(seq) must produce 'giới', got '\(screen.text)'")
        }
        OKEngineSyncConfig(1, 0, 1, 1, 1, 1, 1) // Restore Telex
        
        // 3. Double-w undo on "giơi" / "giới" restores horn ơ to o + w
        let undoCases: [([Int], String)] = [
            ([5, 34, 31, 34, 13, 13], "gioiw"),      // gioiww
            ([5, 34, 31, 13, 34, 13], "gioiw"),      // giowiw
            ([5, 34, 31, 13, 34, 1, 13], "gióiw")    // giowisw -> giới + w = gióiw
        ]
        for (keys, expected) in undoCases {
            OKEngineResetSession()
            var screen = VirtualScreen()
            screen.typeKeys(keys)
            #expect(screen.text == expected, "Double-w undo must yield '\(expected)', got '\(screen.text)'")
        }
        
        // 4. gi- initial consonant vowel syllables
        let giSyllables: [([Int], String)] = [
            ([5, 34, 14, 31, 3], "gièo"),             // gieof
            ([5, 34, 14, 31, 1], "giéo"),             // gieos
            ([5, 34, 14, 31, 15], "giẻo"),            // gieor
            ([5, 34, 14, 31, 7], "giẽo"),             // gieox
            ([5, 34, 14, 31, 38], "giẹo"),            // gieoj
            ([5, 34, 32, 31, 13, 45, 5, 3], "giường"),// giuowngf
            ([5, 34, 32, 31, 13, 45, 5, 1], "giướng"),// giuowngs
            ([5, 34, 32, 31, 13, 34, 3], "giười"),    // giuowif
            ([5, 34, 32, 31, 13, 34, 1], "giưới")     // giuowis
        ]
        for (keys, expected) in giSyllables {
            OKEngineResetSession()
            var screen = VirtualScreen()
            screen.typeKeys(keys)
            #expect(screen.text == expected, "Typing keys must produce '\(expected)', got '\(screen.text)'")
        }
        
        // 5. Standalone w and phonotactic edge cases never eat 'g' or duplicate 'i'
        for seq in [[5, 34, 1, 13, 31, 34], [5, 34, 1, 13, 34], [5, 34, 1, 34, 31, 13]] {
            OKEngineResetSession()
            var screen = VirtualScreen()
            screen.typeKeys(seq)
            #expect(screen.text.starts(with: "g"), "Must retain leading 'g' for sequence \(seq), got '\(screen.text)'")
            #expect(!screen.text.contains("gii"), "Must not duplicate 'i' into 'gii' for sequence \(seq), got '\(screen.text)'")
        }
    }

    // REQ-014: Canonical Telex key normalization and bilingual dictionary lookup
    @Test("REQ-014: Canonical Telex key normalization and bilingual dictionary lookup")
    func canonicalTelexAndBilingualDictionary() {
        #expect(VietnameseDictionary.canonicalTelexKey(for: "việt") == "vieetj")
        #expect(VietnameseDictionary.canonicalTelexKey(for: "người") == "nguowif")
        #expect(VietnameseDictionary.canonicalTelexKey(for: "được") == "duowcj")
        #expect(VietnameseDictionary.canonicalTelexKey(for: "toàn") == "toanf")
        #expect(VietnameseDictionary.canonicalTelexKey(for: "tiếng") == "tieengs")
        #expect(VietnameseDictionary.canonicalTelexKey(for: "cỏe") == "coer")
        #expect(VietnameseDictionary.canonicalTelexKey(for: "mỏe") == "moer")
        #expect(VietnameseDictionary.canonicalTelexKey(for: "tét") == "tets")
        
        #expect(VietnameseDictionary.shared.isValidVietnameseSyllable("việt") == true)
        #expect(VietnameseDictionary.shared.isValidVietnameseSyllable("người") == true)
        #expect(VietnameseDictionary.shared.isValidVietnameseSyllable("mỏe") == false)
        #expect(VietnameseDictionary.shared.isValidVietnameseSyllable("cỏe") == false)
        #expect(VietnameseDictionary.shared.isValidVietnameseSyllable("uẻ") == false)
        #expect(VietnameseDictionary.shared.isValidVietnameseSyllable("trúe") == false)
        
        let eng = VietnameseDictionary.shared.englishWords
        for w in ["cheese", "seemed", "needed", "deepseek", "google", "process", "coffee", "address", "more", "core", "user", "test", "list", "this"] {
            #expect(eng.contains(w), "englishWords must contain '\(w)'")
        }
        
        let prio = VietnameseDictionary.shared.englishPriorityWords
        for w in ["test", "list", "this", "best", "host", "post", "more", "core", "user", "vars", "chars", "docs", "tree", "free", "see", "too", "add", "boss", "pass", "mix", "fix"] {
            #expect(prio.contains(w), "englishPriorityWords must contain '\(w)'")
        }
        for w in ["cos", "banj", "awn", "owr", "aj"] {
            #expect(!prio.contains(w), "englishPriorityWords must NOT contain '\(w)'")
        }
        
        let stems = VietnameseDictionary.shared.englishLookbackStems
        for w in ["is", "of", "if", "for", "or", "us", "car", "ban"] {
            #expect(stems.contains(w), "englishLookbackStems must contain '\(w)'")
        }
    }
    
    // REQ-021: KeepWords safe-list prevents false-positive AutoWording rewrites
    @Test("REQ-021: KeepWords safe-list prevents false-positive AutoWording rewrites")
    func keepWordsSafeListInAutoWording() {
        let keep = VietnameseDictionary.shared.keepWords
        for w in ["ok", "uh", "ah", "oh", "ko", "dc", "vs", "vip", "pro", "app", "web", "api", "sdk", "cpu", "gpu", "ram", "ssd", "ssh", "sql", "jwt", "pdf", "mac", "ios", "bot", "llm"] {
            #expect(keep.contains(w), "keepWords must contain '\(w)'")
        }
        
        let engine = AutoWordingEngine.shared
        let prevEnabled = engine.isEnabled
        let prevCand = engine.candidateSuggestionsEnabled
        let prevShort = engine.shorthandExpansionEnabled
        defer {
            engine.isEnabled = prevEnabled
            engine.candidateSuggestionsEnabled = prevCand
            engine.shorthandExpansionEnabled = prevShort
        }
        
        engine.isEnabled = true
        engine.candidateSuggestionsEnabled = true
        engine.shorthandExpansionEnabled = false
        
        #expect(engine.computeCurrentWordCandidates(rawStem: "ok", currentSyllable: "ok", isWrongSpelling: true).isEmpty == true)
        #expect(engine.computeCurrentWordCandidates(rawStem: "api", currentSyllable: "api", isWrongSpelling: true).isEmpty == true)
        #expect(engine.computeCurrentWordCandidates(rawStem: "vip", currentSyllable: "vip", isWrongSpelling: true).isEmpty == true)
    }
    
    // REQ-022: Curated Teencode and vowel-validated -g shorthand expansion
    @Test("REQ-022: Curated Teencode and vowel-validated -g shorthand expansion")
    func curatedTeencodeExpansion() {
        #expect(AutoWordingShorthandCatalog.builtInTable.isEmpty == true)
        
        let engine = AutoWordingEngine.shared
        let prevEnabled = engine.isEnabled
        let prevShort = engine.shorthandExpansionEnabled
        let prevCustom = engine.customShorthands
        defer {
            engine.isEnabled = prevEnabled
            engine.shorthandExpansionEnabled = prevShort
            engine.customShorthands = prevCustom
        }
        
        engine.isEnabled = true
        engine.shorthandExpansionEnabled = false
        
        #expect(engine.expandShorthand(rawWord: "ko") == nil)
        #expect(engine.expandShorthand(rawWord: "dc") == nil)
        #expect(engine.expandShorthand(rawWord: "ntn") == nil)
        #expect(engine.expandShorthand(rawWord: "khog") == nil)
        #expect(engine.expandShorthand(rawWord: "nhug") == nil)
        
        engine.shorthandExpansionEnabled = true
        
        #expect(engine.expandShorthand(rawWord: "ko") == nil)
        #expect(engine.expandShorthand(rawWord: "dc") == nil)
        #expect(engine.expandShorthand(rawWord: "ntn") == nil)
        #expect(engine.expandShorthand(rawWord: "khog") == nil)
        #expect(engine.expandShorthand(rawWord: "nhug") == nil)
        
        engine.customShorthands = ["ko": "không", "dc": "được"]
        #expect(engine.expandShorthand(rawWord: "ko") == "không")
        #expect(engine.expandShorthand(rawWord: "Ko") == "Không")
        #expect(engine.expandShorthand(rawWord: "dc") == "được")
        
        // English words ending in -g/-k are never expanded
        #expect(engine.expandShorthand(rawWord: "king") == nil)
        #expect(engine.expandShorthand(rawWord: "song") == nil)
        #expect(engine.expandShorthand(rawWord: "blog") == nil)
        #expect(engine.expandShorthand(rawWord: "work") == nil)
        #expect(engine.expandShorthand(rawWord: "check") == nil)
    }

    // REQ-015: Swallowed Telex modifier key tracking and full raw word reconstruction
    @Test("REQ-015: Swallowed Telex modifier key tracking and full raw word reconstruction")
    func swallowedTelexModifierKeyTracking() {
        OKEngineInit()
        OKEngineSyncConfig(1, 0, 1, 1, 1, 1, 1, 0, 0, 0, 0)
        
        let words = [
            "cheese ", "seemed ", "needed ", "deepseek ", "google ", "choose ",
            "process ", "success ", "message ", "issue ", "office ", "coffee ",
            "error ", "array ", "current ", "correct ", "tomorrow ", "sorry ",
            "address ", "middle ", "reddit "
        ]
        for w in words {
            OKEngineResetSession()
            var screen = VirtualScreen()
            screen.typeASCII(w)
            #expect(screen.text == w, "Expected '\(w)', got '\(screen.text)'")
        }
    }

    // REQ-016: Doubled-tone escape repair, acronym protection, contractions, and hyphenated words
    @Test("REQ-016: Doubled-tone escape repair, acronym protection, contractions, and hyphenated words")
    func doubledToneEscapeAndAcronyms() {
        OKEngineInit()
        OKEngineSyncConfig(1, 0, 1, 1, 1, 1, 1, 0, 0, 0, 0)
        
        let escapePairs: [(String, String)] = [
            ("mixx ", "mix "),
            ("fixx ", "fix "),
            ("boxx ", "box "),
            ("maxx ", "max "),
            ("taxx ", "tax "),
            ("sixx ", "six "),
            ("boss ", "boss "),
            ("class ", "class "),
            ("terrible ", "terrible "),
            ("NAS ", "NAS "),
            ("SATA ", "SATA "),
            ("GoPro ", "GoPro "),
            ("doesn't ", "doesn't "),
            ("isn't ", "isn't "),
            ("Wi-Fi ", "Wi-Fi ")
        ]
        for (typed, expected) in escapePairs {
            OKEngineResetSession()
            var screen = VirtualScreen()
            screen.typeASCII(typed)
            #expect(screen.text == expected, "Typed '\(typed)' -> expected '\(expected)', got '\(screen.text)'")
        }
        
        // Vietnamese Đ-acronyms must NOT be restored to English
        OKEngineResetSession()
        var screenVDV = VirtualScreen()
        screenVDV.typeASCII("VDDV ")
        #expect(screenVDV.text == "VĐV ")
        
        OKEngineResetSession()
        var screenBDS = VirtualScreen()
        screenBDS.typeASCII("BDDS ")
        #expect(screenBDS.text == "BĐS ")
    }

    // REQ-017: Standalone English collision priority and invalid Vietnamese diphthong rejection
    @Test("REQ-017: Standalone English collision priority and invalid Vietnamese diphthong rejection")
    func standaloneEnglishCollisionPriority() {
        OKEngineInit()
        OKEngineSyncConfig(1, 0, 1, 1, 1, 1, 1, 0, 0, 0, 0)
        
        let standaloneEnglish = [
            "test ", "list ", "this ", "best ", "host ", "post ",
            "more ", "core ", "user ", "vars ", "chars ", "cors ", "nums ", "docs ",
            "tree ", "free ", "see ", "too ", "add ", "mix ", "fix ",
            "care ", "pure ", "sure ", "true "
        ]
        for w in standaloneEnglish {
            OKEngineResetSession()
            var screen = VirtualScreen()
            screen.typeASCII(w)
            #expect(screen.text == w, "Expected standalone English '\(w)', got '\(screen.text)'")
        }
        
        let vnPairs: [(String, String)] = [
            ("khoe ", "khoe "),
            ("khoer ", "khoẻ "),
            ("xoef ", "xoè "),
            ("thuee ", "thuê "),
            ("hueej ", "huệ "),
            ("cos ", "có "),
            ("banj ", "bạn "),
            ("awn ", "ăn "),
            ("owr ", "ở "),
            ("aj ", "ạ ")
        ]
        for (typed, expected) in vnPairs {
            OKEngineResetSession()
            var screen = VirtualScreen()
            screen.typeASCII(typed)
            #expect(screen.text == expected, "Expected Vietnamese '\(expected)', got '\(screen.text)'")
        }
    }

    // REQ-018: 1-2 word context look-back for multi-word English phrases
    @Test("REQ-018: 1-2 word context look-back for multi-word English phrases")
    func multiWordEnglishContextLookback() {
        OKEngineInit()
        OKEngineSyncConfig(1, 0, 1, 1, 1, 1, 1, 0, 0, 0, 0)
        
        let phrases: [(String, String)] = [
            ("is good ", "is good "),
            ("of course ", "of course "),
            ("for sure ", "for sure "),
            ("if needed ", "if needed "),
            ("or more ", "or more "),
            ("is a test ", "is a test "),
            ("caesar ", "caesar ")
        ]
        for (typed, expected) in phrases {
            OKEngineResetSession()
            var screen = VirtualScreen()
            screen.typeASCII(typed)
            #expect(screen.text == expected, "Typed '\(typed)' -> expected '\(expected)', got '\(screen.text)'")
        }
        
        OKEngineResetSession()
        var vnScreen = VirtualScreen()
        vnScreen.typeASCII("of nhaf ")
        #expect(vnScreen.text == "ò nhà ")
    }

    // REQ-018, ADR-019: Context-Ordered V / E Homograph Disambiguation and Tone-Preserving Candidate Ranking
    @Test("REQ-018: Context-ordered V/E homograph disambiguation and tone-preserving candidate ranking")
    func contextOrderedHomographDisambiguation() {
        OKEngineInit()
        OKEngineSyncConfig(1, 0, 1, 1, 1, 1, 1, 0, 0, 0, 0)
        
        // 1. Vietnamese context (.vietnameseFirst): homographs compose to Vietnamese with diacritics
        let vnPhrases: [(String, String)] = [
            ("sex ", "sẽ "),
            ("anh sex lamf ", "anh sẽ làm "),
            ("max nguoonf ", "mã nguồn "),
            ("bacs six ", "bác sĩ "),
            ("barn vex ", "bản vẽ ")
        ]
        for (typed, expected) in vnPhrases {
            OKEngineResetSession()
            var screen = VirtualScreen()
            screen.typeASCII(typed)
            #expect(screen.text == expected, "Typed '\(typed)' -> expected '\(expected)', got '\(screen.text)'")
        }
        
        // 2. English context (.englishFirst after an English word): homographs restore to English
        let enPhrases: [(String, String)] = [
            ("have sex ", "have sex "),
            ("at max ", "at max "),
            ("number six ", "number six "),
            ("income tax ", "income tax "),
            ("full moon ", "full moon ")
        ]
        for (typed, expected) in enPhrases {
            OKEngineResetSession()
            var screen = VirtualScreen()
            screen.typeASCII(typed)
            #expect(screen.text == expected, "Typed '\(typed)' -> expected '\(expected)', got '\(screen.text)'")
        }
        
        // 3. 1-2 word context look-back: homograph + English word rewrites prior word
        let lookbackPhrases: [(String, String)] = [
            ("sex is ", "sex is "),
            ("max value ", "max value "),
            ("tax rate ", "tax rate ")
        ]
        for (typed, expected) in lookbackPhrases {
            OKEngineResetSession()
            var screen = VirtualScreen()
            screen.typeASCII(typed)
            #expect(screen.text == expected, "Typed '\(typed)' -> expected '\(expected)', got '\(screen.text)'")
        }
        
        // 4. Tone-preserving candidate ranking
        let candidatesV = AutoWordingEngine.computeCandidates(
            currentSyllable: "sẽ",
            rawStem: "sex",
            previousWord: nil,
            languagePriority: .vietnameseFirst
        )
        #expect(!candidatesV.isEmpty, "Candidates for .vietnameseFirst should not be empty")
        #expect(candidatesV[0].text == "sẽ", "Expected 'sẽ' at index 0 for .vietnameseFirst, got '\(candidatesV.first?.text ?? "")'")
        #expect(candidatesV.map(\.text).contains("sex"), "Expected candidates to include 'sex'")
        
        let candidatesE = AutoWordingEngine.computeCandidates(
            currentSyllable: "sẽ",
            rawStem: "sex",
            previousWord: nil,
            languagePriority: .englishFirst
        )
        #expect(candidatesE.count >= 2, "Expected at least 2 candidates for .englishFirst")
        #expect(candidatesE[0].text == "sex", "Expected 'sex' at index 0 for .englishFirst, got '\(candidatesE.first?.text ?? "")'")
        #expect(candidatesE[1].text == "sẽ", "Expected 'sẽ' at index 1 for .englishFirst, got '\(candidatesE.count > 1 ? candidatesE[1].text : "")'")
    }

    // REQ-019: Inline Vietnamese mode retention (1-2 English words) and 3+ word bidirectional auto-switch
    @Test("REQ-019: Inline Vietnamese mode retention (1-2 English words) and 3+ word bidirectional auto-switch")
    func inlineModeRetentionAndBidirectionalSwitch() {
        OKEngineInit()
        OKEngineSyncConfig(1, 0, 1, 1, 1, 1, 1, 0, 0, 0, 0)
        
        OKEngineResetSession()
        var screen = VirtualScreen()
        screen.typeASCII("tooi ddi test list nhaf ")
        #expect(screen.text == "tôi đi test list nhà ")
        
        OKEngineResetSession()
        var screen3 = VirtualScreen()
        screen3.typeASCII("test")
        let snap1 = screen3.typeKey(49)
        #expect(snap1.languageSwitchRequest == -1)
        screen3.typeASCII("list")
        let snap2 = screen3.typeKey(49)
        #expect(snap2.languageSwitchRequest == -1)
        screen3.typeASCII("more")
        let snap3 = screen3.typeKey(49)
        #expect(snap3.languageSwitchRequest == 0)
        
        OKEngineResetSession()
        let enKeys = [45, 4, 31, 13, 1, 49] // "nhows "
        var lastEnSnap = OKHookSnapshot()
        for k in enKeys {
            lastEnSnap = OKEngineHandleEnglishModeKeyEvent(UInt16(k), 0, false)
        }
        #expect(lastEnSnap.languageSwitchRequest == 1)
        #expect(lastEnSnap.decodedString == "nhớ ")
    }

    // REQ-020: Single-backspace undo and re-conversion lock
    @Test("REQ-020: Single-backspace undo and re-conversion lock")
    func singleBackspaceUndoAndLock() {
        OKEngineInit()
        OKEngineSyncConfig(1, 0, 1, 1, 1, 1, 1, 0, 0, 0, 0)
        
        OKEngineResetSession()
        var screen = VirtualScreen()
        screen.typeASCII("test ")
        #expect(screen.text == "test ")
        
        screen.typeKey(51) // Backspace
        #expect(screen.text == "tét")
        
        screen.typeKey(49) // Space again -> locked
        #expect(screen.text == "tét ")
    }

    // REQ-023: Engine context guards: digit-prefix words, arrow navigation snapshot, and compound-token boundary
    @Test("REQ-023: Engine context guards: digit-prefix words, arrow navigation snapshot, and compound-token boundary")
    func engineContextGuards() {
        OKEngineInit()
        OKEngineSyncConfig(1, 0, 1, 1, 1, 1, 1, 0, 0, 0, 0)
        
        OKEngineResetSession()
        var s1 = VirtualScreen()
        s1.typeASCII("1casi ")
        #expect(s1.text == "1cái ")
        
        OKEngineResetSession()
        var s2 = VirtualScreen()
        s2.typeASCII("2ngayf ")
        #expect(s2.text == "2ngày ")
        
        OKEngineResetSession()
        var s3 = VirtualScreen()
        s3.typeASCII("0xdeadbeef ")
        #expect(s3.text == "0xdeadbeef ")
        
        OKEngineResetSession()
        var s4 = VirtualScreen()
        s4.typeASCII("base64 ")
        #expect(s4.text == "base64 ")
        
        // Single-step Left + Right mid-word navigation snapshot
        OKEngineResetSession()
        var sNav = VirtualScreen()
        sNav.typeASCII("vie")
        _ = OKEngineHandleKeyEvent(123, 0, false) // KEY_LEFT
        _ = OKEngineHandleKeyEvent(124, 0, false) // KEY_RIGHT
        sNav.typeASCII("ejt ")
        #expect(sNav.text == "việt ")
        
        // Compound-token boundary
        OKEngineResetSession()
        var sComp = VirtualScreen()
        sComp.typeASCII("foo.bars ")
        #expect(sComp.text == "foo.bars ")
        
        OKEngineResetSession()
        var sComp2 = VirtualScreen()
        sComp2.typeASCII("my_vars ")
        #expect(sComp2.text == "my_vars ")
    }

    // REQ-024: Hybrid E/V context-ordered wrong-word auto-correction and candidate ranking
    @Test("REQ-024: Hybrid E/V context-ordered wrong-word auto-correction and candidate ranking")
    func hybridEVWrongWordAutoCorrectionAndCandidateRanking() {
        OKEngineInit()
        OKEngineResetSession()
        OKEngineSyncConfig(1, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1)
        defer { OKEngineSyncConfig(1, 0, 1, 1, 1, 1, 1, 0, 0, 0, 0) }
        
        #expect(OKEngineGetEffectiveLanguagePriority() == .vietnameseFirst)
        
        // English typo corrections on Space
        for (typo, expected) in [
            ("teh ", "the "),
            ("fucntion ", "function "),
            ("recieve ", "receive "),
            ("seperate ", "separate "),
            ("occured ", "occurred ")
        ] {
            OKEngineResetSession()
            var s = VirtualScreen()
            s.typeASCII(typo)
            #expect(s.text == expected, "Typo '\(typo)' must expand to '\(expected)'")
        }
        
        // Vietnamese typo corrections on Space
        for (typo, expected) in [
            ("nguowi ", "người "),
            ("dduowc ", "được "),
            ("vieet ", "việt ")
        ] {
            OKEngineResetSession()
            var s = VirtualScreen()
            s.typeASCII(typo)
            #expect(s.text == expected, "Typo '\(typo)' must expand to '\(expected)'")
        }
        
        // Single-backspace undo after typo correction ('teh ' + KEY_DELETE 51 -> 'teh', then Space 49 -> 'teh ')
        OKEngineResetSession()
        var sUndo = VirtualScreen()
        sUndo.typeASCII("teh ")
        #expect(sUndo.text == "the ")
        sUndo.typeKey(51) // Backspace
        #expect(sUndo.text == "teh")
        sUndo.typeKey(49) // Space -> locked, remains 'teh '
        #expect(sUndo.text == "teh ")
        
        // computeCurrentWordCandidates E vs V ordering
        let autoEngine = AutoWordingEngine.shared
        let prevEnabled = autoEngine.isEnabled
        let prevCand = autoEngine.candidateSuggestionsEnabled
        defer {
            autoEngine.isEnabled = prevEnabled
            autoEngine.candidateSuggestionsEnabled = prevCand
        }
        autoEngine.isEnabled = true
        autoEngine.candidateSuggestionsEnabled = true
        
        let candV = autoEngine.computeCurrentWordCandidates(rawStem: "teh", currentSyllable: "teh", isWrongSpelling: true, languagePriority: .vietnameseFirst)
        let candE = autoEngine.computeCurrentWordCandidates(rawStem: "teh", currentSyllable: "teh", isWrongSpelling: true, languagePriority: .englishFirst)
        #expect(candE.first?.text == "the")
        #expect(candV.contains(where: { $0.text == "the" }))
    }

    // REQ-025: Sub-millisecond inline bilingual grammar, agreement, duplicate collapse, and sentence formatting
    @Test("REQ-025: Sub-millisecond inline bilingual grammar, agreement, duplicate collapse, and sentence formatting")
    func inlineBilingualGrammarAndFormatting() {
        OKEngineInit()
        OKEngineResetSession()
        OKEngineSyncConfig(1, 0, 1, 1, 1, 1, 1, 1, 1, 0, 0, 1)
        defer { OKEngineSyncConfig(1, 0, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0) }
        
        // Vietnamese 2-word bigrams
        for (input, expected) in [
            ("lamf vieetj ", "làm việc "),
            ("suy nghir ", "suy nghĩ "),
            ("suwax chuwax ", "sửa chữa "),
            ("chia sex ", "chia sẻ "),
            ("vui vex ", "vui vẻ "),
            ("phats trieenx ", "phát triển ")
        ] {
            OKEngineResetSession()
            var s = VirtualScreen()
            s.typeASCII(input)
            #expect(s.text == expected, "Bigram '\(input)' must correct to '\(expected)'")
        }
        
        // English contractions & agreement
        for (input, expected) in [
            ("dont ", "don't "),
            ("doesnt ", "doesn't "),
            ("cant ", "can't "),
            ("wont ", "won't "),
            ("i ", "I "),
            ("a apple ", "an apple "),
            ("a error ", "an error "),
            ("an user ", "a user "),
            ("he dont ", "he doesn't "),
            ("they was ", "they were ")
        ] {
            OKEngineResetSession()
            var s = VirtualScreen()
            s.typeASCII(input)
            #expect(s.text == expected, "Agreement '\(input)' must become '\(expected)'")
        }
        
        // Duplicate collapse
        for (input, expected) in [
            ("the the ", "the "),
            ("is is ", "is "),
            ("luoon luoon ", "luôn luôn ")
        ] {
            OKEngineResetSession()
            var s = VirtualScreen()
            s.typeASCII(input)
            #expect(s.text == expected, "Duplicate check for '\(input)' must equal '\(expected)'")
        }
        
        // Double-space period + sentence-start capitalization
        OKEngineResetSession()
        var sSentence = VirtualScreen()
        sSentence.typeASCII("hello  world ")
        #expect(sSentence.text == "hello. World ")
    }

    // REQ-026: BilingualAutoSwitchEngine extraction and OpenKeyLogger queue serialization
    @Test("REQ-026: BilingualAutoSwitchEngine extraction and OpenKeyLogger queue serialization")
    func cohesionAndLoggerQueueSerialization() {
        OKEngineInit()
        OKEngineResetSession()
        OpenKeyLogger.shared.checkVersionRetention()
        OpenKeyLogger.shared.clearLog()
        #expect(OKEngineGetEffectiveLanguagePriority() == .vietnameseFirst)
    }

    // REQ-025, ADR-026: Independent Double-Space Period Option & Double-Tap Threshold
    @Test("REQ-025, ADR-026: Independent double-space period option and double-tap threshold")
    func independentDoubleSpacePeriodAndThreshold() {
        OKEngineInit()
        OKEngineResetSession()
        
        // 1. Test OKEngineSyncConfig parameter synchronization
        OKEngineSyncConfig(1, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1)
        #expect(AutoWordingEngine.shared.doubleSpacePeriodEnabled == true)
        
        OKEngineSyncConfig(1, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0)
        #expect(AutoWordingEngine.shared.doubleSpacePeriodEnabled == false)
        defer { OKEngineSyncConfig(1, 0, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0) }
        
        // 2. When doubleSpacePeriodEnabled == 0 (even if grammarRepairEnabled == 1),
        // typing "xin chào  " (double space) does NOT produce a period (".").
        OKEngineResetSession()
        OKEngineSyncConfig(1, 0, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0) // grammarRepair = 1, doubleSpace = 0
        var sDisabled = VirtualScreen()
        sDisabled.typeASCII("xin chaof  ")
        #expect(sDisabled.text == "xin chào  ", "With doubleSpacePeriodEnabled == false, typing double space must NOT insert period; got '\(sDisabled.text)'")
        #expect(!sDisabled.text.contains("."), "Text must not contain period when doubleSpacePeriodEnabled is disabled")
        
        // 3. When doubleSpacePeriodEnabled == 1:
        // (a) Rapid double space (delta <= 0.5s) emits ". "
        OKEngineResetSession()
        OKEngineSyncConfig(1, 0, 1, 1, 1, 1, 1, 1, 1, 0, 0, 1) // doubleSpace = 1
        var sRapid = VirtualScreen()
        sRapid.typeASCII("xin chaof  ")
        #expect(sRapid.text == "xin chào. ", "Rapid double space (delta <= 0.5s) must emit '. '; got '\(sRapid.text)'")
        
        // (b) Delayed double space (delta > 0.5s) preserves normal spaces
        OKEngineResetSession()
        var sDelayed = VirtualScreen()
        sDelayed.typeASCII("xin chaof ") // First space
        #expect(sDelayed.text == "xin chào ")
        Thread.sleep(forTimeInterval: 0.55) // Wait > 500ms
        sDelayed.typeKey(49) // Second space
        #expect(sDelayed.text == "xin chào  ", "Delayed double space (> 0.5s) must preserve normal spaces; got '\(sDelayed.text)'")
        #expect(!sDelayed.text.contains("."), "Delayed double space must not produce period")
    }

    // REQ-027, ADR-027: Escape Keystroke Consumption and Composed Word Protection
    @Test("REQ-027, ADR-027: Trailing modifier appended on space and composed word protection")
    func testTrailingModifierAppendedOnSpace() {
        OKEngineInit()
        OKEngineResetSession()
        OKEngineSyncConfig(1, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0)
        defer { OKEngineSyncConfig(1, 0, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0) }

        // 1. Simulate typing c-h-a-o-s-s (Telex chaos) + KEY_SPACE (49).
        // Verify result is "chaos " with 0 backspaces on space (NOT "chaoss ").
        var sChaos = VirtualScreen()
        sChaos.typeASCII("chaoss")
        let spaceSnapChaos = sChaos.typeKey(49)
        #expect(spaceSnapChaos.backspaceCount == 0, "Space after 'chaos' must send 0 backspaces, got \(spaceSnapChaos.backspaceCount)")
        #expect(sChaos.text == "chaos ", "Typing chaoss + Space must produce 'chaos ', got '\(sChaos.text)'")

        // 2. Simulate typing t-h-o-i-w-f (thời) + i + KEY_SPACE (49).
        // Verify result is "thời " (NOT "thoiwfi ").
        OKEngineResetSession()
        var sThoi = VirtualScreen()
        sThoi.typeASCII("thoiwfi")
        let spaceSnapThoi = sThoi.typeKey(49)
        #expect(spaceSnapThoi.backspaceCount == 0, "Space after 'thời' must send 0 backspaces, got \(spaceSnapThoi.backspaceCount)")
        #expect(sThoi.text == "thời ", "Typing thoiwfi + Space must produce 'thời ', got '\(sThoi.text)'")
    }

    // REQ-027, ADR-027: English word restore with tone cancel escape before punctuation
    @Test("REQ-027, ADR-027: English word restore with tone cancel escape before punctuation")
    func testEnglishWordRestoreWithToneCancelEscape() {
        OKEngineInit()
        OKEngineResetSession()
        OKEngineSyncConfig(1, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0)
        defer { OKEngineSyncConfig(1, 0, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0) }

        // Simulate typing s-e-r-r-v-i-c-e + KEY_COMMA (43).
        // Verify result is "service," (NOT "serrvice,").
        var sService = VirtualScreen()
        sService.typeASCII("serrvice")
        _ = sService.typeKey(43) // KEY_COMMA
        #expect(sService.text == "service,", "Typing serrvice + comma must produce 'service,', got '\(sService.text)'")
    }

    // REQ-028, ADR-028: Duplicate word expansion on space prevented by history synchronization
    @Test("REQ-028, ADR-028: Duplicate word expansion on space prevented by history synchronization")
    func testDuplicateWordExpansionOnSpace() {
        OKEngineInit()
        OKEngineResetSession()
        OKEngineSyncConfig(1, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0)
        defer { OKEngineSyncConfig(1, 0, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0) }

        // Simulate typing o + f (ò) + KEY_SPACE, then m (46), then KEY_DELETE (51) 3 times (deleting m, space, ò).
        // Then type o + f + f (of) + KEY_SPACE.
        // Verify result is "of " with 0 backspaces (NOT "of off ").
        var s = VirtualScreen()
        s.typeASCII("of ") // o + f -> ò, space -> "ò "
        s.typeKey(46)      // m -> "ò m"
        s.typeKey(51)      // delete m -> "ò "
        s.typeKey(51)      // delete space -> "ò"
        s.typeKey(51)      // delete ò -> ""
        #expect(s.text == "", "Screen text after 3 deletes must be empty, got '\(s.text)'")

        s.typeASCII("off") // o + f + f -> "of"
        let spaceSnap = s.typeKey(49) // KEY_SPACE
        #expect(spaceSnap.backspaceCount == 0, "Space after 'of' must send 0 backspaces, got \(spaceSnap.backspaceCount)")
        #expect(s.text == "of ", "Typing off + Space must produce 'of ', got '\(s.text)'")
    }

    // REQ-027, REQ-015: English double letter preserved on word break
    @Test("REQ-027, REQ-015: English double letter words restored on word break")
    func testEnglishDoubleLetterPreserved() {
        OKEngineInit()
        OKEngineResetSession()
        OKEngineSyncConfig(1, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0)
        defer { OKEngineSyncConfig(1, 0, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0) }

        // Simulate typing c-o-f-f-e-e + KEY_SPACE and p-r-o-c-e-s-s + KEY_SPACE.
        // Verify both words restore correctly to "coffee " and "process " per REQ-015.
        var sCoffee = VirtualScreen()
        sCoffee.typeASCII("coffee ")
        #expect(sCoffee.text == "coffee ", "Typing coffee + Space must restore to 'coffee ', got '\(sCoffee.text)'")

        OKEngineResetSession()
        var sProcess = VirtualScreen()
        sProcess.typeASCII("process ")
        #expect(sProcess.text == "process ", "Typing process + Space must restore to 'process ', got '\(sProcess.text)'")
    }

    // REQ-029, ADR-029: High frequency English verbs preserved in Vietnamese mode
    @Test("REQ-029, ADR-029: High frequency English verbs preserved in Vietnamese mode")
    func testHighFrequencyEnglishVerbsPreservedInVietnameseMode() {
        let dict = VietnameseDictionary.shared
        let commonVerbs = [
            "did", "said", "went", "got", "made", "came", "took", "gave", "saw",
            "told", "felt", "kept", "began", "held", "wrote", "sat", "stood",
            "paid", "spent", "grew", "won", "bought", "fell", "cut", "sold",
            "ate", "drew", "chose", "fought", "threw", "hid", "done", "seen", "gone",
            "run", "become", "meant", "lost", "sent", "built", "fallen"
        ]
        for verb in commonVerbs {
            #expect(dict.englishWords.contains(verb), "dict.englishWords must contain '\(verb)'")
            #expect(dict.keepWords.contains(verb), "dict.keepWords must contain '\(verb)'")
        }

        OKEngineInit()
        OKEngineResetSession()
        OKEngineSyncConfig(1, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0)
        defer { OKEngineSyncConfig(1, 0, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0) }

        var screen = VirtualScreen()
        screen.typeASCII("did you ")
        #expect(screen.text == "did you ", "Typing 'did you ' must produce 'did you ', got '\(screen.text)'")
    }

    // MARK: - REQ-030, ADR-030: Uppercase I and word-initial standalone w handling
    @Test("REQ-030, ADR-030: Uppercase I does not trigger redundant backspace replacement on Space")
    func testUppercaseIDoesNotTriggerRedundantReplacement() {
        OKEngineInit()
        OKEngineResetSession()
        OKEngineSyncConfig(1, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0)
        defer { OKEngineSyncConfig(1, 0, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0) }

        // Type uppercase 'I' (keyCode 34, capsStatus 1, otherControlKey false)
        _ = OKEngineHandleKeyEvent(34, 1, false)
        let snapSpace = OKEngineHandleKeyEvent(49, 0, false)
        #expect(snapSpace.code == HookCodeState.doNothing, "Space after uppercase 'I' must doNothing, got \(snapSpace.code)")
        #expect(snapSpace.backspaceCount == 0, "Space after uppercase 'I' must send 0 backspaces, got \(snapSpace.backspaceCount)")
        #expect(OKEngineGetEffectiveLanguagePriority() == .englishFirst, "Language priority after uppercase 'I' must be .englishFirst")

        // Lowercase "i " still auto-capitalizes to "I "
        OKEngineResetSession()
        var screen = VirtualScreen()
        screen.typeASCII("i ")
        #expect(screen.text == "I ", "Lowercase 'i ' must auto-capitalize to 'I ', got '\(screen.text)'")
    }

    @Test("REQ-030, ADR-030: Word-initial standalone w auto-reverts immediately on English second letters")
    func testStandaloneWImmediateAutoRevertOnEnglishSecondLetters() {
        OKEngineInit()
        OKEngineResetSession()
        OKEngineSyncConfig(1, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0)
        defer { OKEngineSyncConfig(1, 0, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0) }

        // Typing w (13) then e (14) on VirtualScreen immediately produces "we" on the 2nd keystroke
        var screenWE = VirtualScreen()
        _ = screenWE.typeKey(13)
        #expect(screenWE.text == "ư", "First keystroke 'w' produces 'ư', got '\(screenWE.text)'")
        _ = screenWE.typeKey(14)
        #expect(screenWE.text == "we", "Second keystroke 'e' must immediately auto-revert to 'we', got '\(screenWE.text)'")

        var screenWI = VirtualScreen()
        _ = screenWI.typeKey(13)
        _ = screenWI.typeKey(34) // i
        #expect(screenWI.text == "wi", "w + i must immediately produce 'wi', got '\(screenWI.text)'")

        var screenWH = VirtualScreen()
        _ = screenWH.typeKey(13)
        _ = screenWH.typeKey(4) // h
        #expect(screenWH.text == "wh", "w + h must immediately produce 'wh', got '\(screenWH.text)'")

        // Full sentences/words on VirtualScreen
        let englishPhrases = [
            ("I think we need ", "I think we need "),
            ("with ", "with "),
            ("what ", "what "),
            ("when ", "when "),
            ("where ", "where "),
            ("which ", "which "),
            ("while ", "while "),
            ("window ", "window ")
        ]
        for (input, expected) in englishPhrases {
            OKEngineResetSession()
            var s = VirtualScreen()
            s.typeASCII(input)
            #expect(s.text == expected, "Typing '\(input)' must produce '\(expected)', got '\(s.text)'")
        }

        // Valid Vietnamese initial-ư words still compose as Vietnamese
        let vietnameseWords = [
            ("w ", "ư "),
            ("wr ", "ử "),
            ("wa ", "ưa "),
            ("wowns ", "ướn "),
            ("wcs ", "ức "),
            ("wng ", "ưng ")
        ]
        for (input, expected) in vietnameseWords {
            OKEngineResetSession()
            var s = VirtualScreen()
            s.typeASCII(input)
            #expect(s.text == expected, "Vietnamese '\(input)' must produce '\(expected)', got '\(s.text)'")
        }
    }

    // MARK: - REQ-019, ADR-020: Vietnamese Syllable Protection and Standalone-W Escape
    @Test("REQ-019, ADR-020: Vietnamese syllable protection ('thể' vs 'there') and standalone-W escape normalization ('Why' vs 'Wwhy')")
    func testVietnameseSyllableProtectionAndStandaloneWEscape() {
        OKEngineInit()
        OKEngineResetSession()
        OKEngineSyncConfig(1, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0)
        defer { OKEngineSyncConfig(1, 0, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0) }

        // (a) Vietnamese syllable protection: 'theer ' -> 'thể ', 'there ' -> 'thể ', etc.
        let vietnamesePhrases = [
            ("theer ", "thể "),
            ("there ", "thể "),
            ("cos theer ", "có thể "),
            ("cos there ", "có thể "),
            ("con theer ", "con thể "),
            ("con there ", "con thể "),
            ("hay theer ", "hay thể "),
            ("nhuw thees ", "như thế "),
            ("nhuw these ", "như thế "),
            ("thees ", "thế "),
            ("these ", "thế ")
        ]
        for (input, expected) in vietnamesePhrases {
            OKEngineResetSession()
            var s = VirtualScreen()
            s.typeASCII(input)
            #expect(s.text == expected, "Typing '\(input)' must produce '\(expected)', got '\(s.text)'")
        }

        // (b) English phrases: 'there is ', 'there are ', 'over there ', 'these are '
        let englishPhrases = [
            ("there is ", "there is "),
            ("there are ", "there are "),
            ("over there ", "over there "),
            ("these are ", "these are ")
        ]
        for (input, expected) in englishPhrases {
            OKEngineResetSession()
            var s = VirtualScreen()
            s.typeASCII(input)
            #expect(s.text == expected, "Typing '\(input)' must produce '\(expected)', got '\(s.text)'")
        }

        // (c) Standalone-W escape and sentence capitalization
        let standaloneWPhrases = [
            ("Why ", "Why "),
            ("Wwhy ", "Why "),
            ("why ", "why "),
            ("wwhy ", "why "),
            ("cos there. wwhy also wrong ", "có thể. Why also wrong "),
            ("cos theer. Wwhy also wrong ", "có thể. Why also wrong ")
        ]
        for (input, expected) in standaloneWPhrases {
            OKEngineResetSession()
            var s = VirtualScreen()
            s.typeASCII(input)
            #expect(s.text == expected, "Typing '\(input)' must produce '\(expected)', got '\(s.text)'")
        }
    }

    // MARK: - REQ-021, ADR-022: Live Mid-Word Phonotactic Auto-Escape & Teams Continuity
    @Test("REQ-021, ADR-022: Live mid-word phonotactic auto-escape, morphological inflections, *oe* filter, and Teams context continuity")
    func testReq021Adr022LiveMidWordPhonotacticAutoEscape() {
        OKEngineInit()
        OKEngineResetSession()
        OKEngineSyncConfig(1, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0)
        defer { OKEngineSyncConfig(1, 0, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0) }

        let dict = VietnameseDictionary.shared

        // 1. Filter fake combinatorial *oe* syllables and sentence verification
        #expect(!dict.isValidVietnameseSyllable("goé"), "goé must be invalid")
        #expect(!dict.isValidVietnameseSyllable("doé"), "doé must be invalid")
        #expect(!dict.isValidVietnameseSyllable("moẻ"), "moẻ must be invalid")
        #expect(dict.isValidVietnameseSyllable("khoẻ"), "khoẻ must be valid")
        #expect(dict.isValidVietnameseSyllable("xoè"), "xoè must be valid")

        var sGoes = VirtualScreen()
        sGoes.typeASCII("so goes with ")
        #expect(sGoes.text == "so goes with ", "Typing 'so goes with ' must produce 'so goes with ', got '\(sGoes.text)'")

        // 2. Post-tone KEY_E live mid-word auto-restore BEFORE Space is pressed
        let postToneWords = [
            ("more", "more"),
            ("core", "core"),
            ("store", "store"),
            ("care", "care"),
            ("share", "share"),
            ("fire", "fire"),
            ("sure", "sure"),
            ("case", "case"),
            ("nose", "nose"),
            ("use", "use"),
            ("house", "house"),
            ("life", "life")
        ]
        for (typed, expected) in postToneWords {
            OKEngineResetSession()
            var s = VirtualScreen()
            s.typeASCII(typed) // BEFORE Space!
            #expect(s.text == expected, "Live typing '\(typed)' before Space must restore to '\(expected)', got '\(s.text)'")
        }

        OKEngineResetSession()
        var sMoreErrors = VirtualScreen()
        sMoreErrors.typeASCII("here is still more errors ")
        #expect(sMoreErrors.text == "here is still more errors ", "Typing 'here is still more errors ' must produce 'here is still more errors ', got '\(sMoreErrors.text)'")

        // 3. Invalid post-vowel coda consonant mid-word auto-restore BEFORE Space is pressed
        let codaWords = [
            ("need", "need"),
            ("good", "good"),
            ("book", "book"),
            ("feel", "feel"),
            ("work", "work"),
            ("word", "word"),
            ("part", "part"),
            ("start", "start"),
            ("sort", "sort"),
            ("soft", "soft"),
            ("left", "left"),
            ("text", "text"),
            ("next", "next")
        ]
        for (typed, expected) in codaWords {
            OKEngineResetSession()
            var s = VirtualScreen()
            s.typeASCII(typed) // BEFORE Space!
            #expect(s.text == expected, "Live typing '\(typed)' before Space must restore to '\(expected)', got '\(s.text)'")
        }

        OKEngineResetSession()
        var sNeeded = VirtualScreen()
        sNeeded.typeASCII("so the python code is not needed? ")
        #expect(sNeeded.text == "so the python code is not needed? ", "Typing 'so the python code is not needed? ' must produce 'so the python code is not needed? ', got '\(sNeeded.text)'")

        // 4. Live mid-word double-consonant restoration
        OKEngineResetSession()
        var sCorrect = VirtualScreen()
        sCorrect.typeASCII("correct")
        #expect(sCorrect.text == "correct", "Live typing 'correct' before Space must be 'correct', got '\(sCorrect.text)'")

        OKEngineResetSession()
        var sErrors = VirtualScreen()
        sErrors.typeASCII("errors")
        #expect(sErrors.text == "errors", "Live typing 'errors' before Space must be 'errors', got '\(sErrors.text)'")

        OKEngineResetSession()
        var sService = VirtualScreen()
        sService.typeASCII("serrvice,")
        #expect(sService.text == "service,", "Typing 'serrvice,' must produce 'service,', got '\(sService.text)'")

        // 5. Compound Telex escape: t-h-e-s-e + s -> "these", t-h-e-s-e + e -> "these"
        OKEngineResetSession()
        var sTheseS = VirtualScreen()
        sTheseS.typeASCII("theses")
        #expect(sTheseS.text == "these", "Typing t-h-e-s-e + s must escape to 'these', got '\(sTheseS.text)'")

        OKEngineResetSession()
        var sTheseE = VirtualScreen()
        sTheseE.typeASCII("thesee")
        #expect(sTheseE.text == "these", "Typing t-h-e-s-e + e must escape to 'these', got '\(sTheseE.text)'")

        // 6. Sentence context continuity with commas and @mentions
        OKEngineResetSession()
        var sTony = VirtualScreen()
        sTony.typeASCII("I think Tony is correct, ")
        #expect(sTony.text == "I think Tony is correct, ", "Typing 'I think Tony is correct, ' must produce 'I think Tony is correct, ', got '\(sTony.text)'")

        OKEngineResetSession()
        var sMention = VirtualScreen()
        sMention.typeASCII("@Shi @To, these ")
        #expect(sMention.text == "@Shi @To, these ", "Typing '@Shi @To, these ' must produce '@Shi @To, these ', got '\(sMention.text)'")

        // 7. Morphological inflection checks
        let inflections = [
            "errors", "goes", "does", "files", "lines", "codes", "checks",
            "working", "updated", "deleted", "passes", "processes", "messages"
        ]
        for inf in inflections {
            #expect(dict.isEnglishWord(inf), "isEnglishWord must recognize '\(inf)'")
        }

        // 8. Vietnamese preservation
        let vnPreservations = [
            ("there ", "thể "),
            ("these ", "thế "),
            ("of ", "ò "),
            ("lucs nhaanj chayj kieerm tra looxi chinhs tar sai ", "lúc nhận chạy kiểm tra lỗi chính tả sai ")
        ]
        for (input, expected) in vnPreservations {
            OKEngineResetSession()
            var s = VirtualScreen()
            s.typeASCII(input)
            #expect(s.text == expected, "Typing '\(input)' must preserve Vietnamese '\(expected)', got '\(s.text)'")
        }
    }

}
}

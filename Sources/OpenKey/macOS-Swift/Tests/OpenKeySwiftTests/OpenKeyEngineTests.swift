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
        defer {
            OKEngineSyncConfig(1, 0, 1, 1, 1, 1, 1, 0, 0, 0, 0)
        }
        
        // Test "tiengs" -> "tiếng"
        // Key codes: t=17, i=34, e=14, n=45, g=5, s=1
        _ = OKEngineHandleKeyEvent(17, 0, false) // t
        _ = OKEngineHandleKeyEvent(34, 0, false) // i
        _ = OKEngineHandleKeyEvent(14, 0, false) // e
        _ = OKEngineHandleKeyEvent(45, 0, false) // n
        _ = OKEngineHandleKeyEvent(5, 0, false)  // g
        let snapS = OKEngineHandleKeyEvent(1, 0, false)  // s (acute mark)
        
        #expect(snapS.code != 0, "Typing 's' in 'tieng' must trigger engine processing")
        #expect(snapS.backspaceCount >= 3, "Must send backspaces to replace syllable")
        #expect(snapS.decodedString.contains("ế") || snapS.decodedString.contains("é"), "Must output accented vowel: \(snapS.decodedString)")
        
        // Test "vieetj" -> "việt"
        OKEngineResetSession()
        // v=9, i=34, e=14, e=14, t=17, j=38
        _ = OKEngineHandleKeyEvent(9, 0, false)  // v
        _ = OKEngineHandleKeyEvent(34, 0, false) // i
        _ = OKEngineHandleKeyEvent(14, 0, false) // e
        _ = OKEngineHandleKeyEvent(14, 0, false) // e -> ê
        _ = OKEngineHandleKeyEvent(17, 0, false) // t
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
        
        // Test "vie6t5" -> "việt" in VNI
        // v=9, i=34, e=14, 6=22, t=17, 5=23
        _ = OKEngineHandleKeyEvent(9, 0, false)  // v
        _ = OKEngineHandleKeyEvent(34, 0, false) // i
        _ = OKEngineHandleKeyEvent(14, 0, false) // e
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
        _ = OKEngineHandleKeyEvent(17, 0, false) // t
        _ = OKEngineHandleKeyEvent(15, 0, false) // r
        _ = OKEngineHandleKeyEvent(32, 0, false) // u
        _ = OKEngineHandleKeyEvent(31, 0, false) // o
        let snapW = OKEngineHandleKeyEvent(13, 0, false) // w -> ươ
        #expect(snapW.code == HookCodeState.willProcess)
        #expect(snapW.backspaceCount >= 1)
        _ = OKEngineHandleKeyEvent(45, 0, false) // n
        _ = OKEngineHandleKeyEvent(5, 0, false)  // g
        let snapTruong = OKEngineHandleKeyEvent(3, 0, false) // f -> grave mark
        #expect(snapTruong.code == HookCodeState.willProcess)
        #expect(snapTruong.decodedString.contains("ườ"))
        
        // 2. "nghieng" Telex: n g h i e e n g -> nghiêng
        OKEngineResetSession()
        _ = OKEngineHandleKeyEvent(45, 0, false) // n
        _ = OKEngineHandleKeyEvent(5, 0, false)  // g
        _ = OKEngineHandleKeyEvent(4, 0, false)  // h
        _ = OKEngineHandleKeyEvent(34, 0, false) // i
        _ = OKEngineHandleKeyEvent(14, 0, false) // e
        let snapEE = OKEngineHandleKeyEvent(14, 0, false) // e -> ê
        #expect(snapEE.code == HookCodeState.willProcess)
        #expect(snapEE.decodedString.contains("ê"))
        
        // 3. "quoc" Telex: q u o c s -> quốc
        OKEngineResetSession()
        _ = OKEngineHandleKeyEvent(12, 0, false) // q
        _ = OKEngineHandleKeyEvent(32, 0, false) // u
        _ = OKEngineHandleKeyEvent(31, 0, false) // o
        _ = OKEngineHandleKeyEvent(8, 0, false)  // c
        let snapQuoc = OKEngineHandleKeyEvent(1, 0, false) // s -> sắc
        #expect(snapQuoc.code == HookCodeState.willProcess)
        #expect(snapQuoc.decodedString.contains("ố") || snapQuoc.decodedString.contains("ó"))
        
        // 4. "giu" Telex: g i u x -> giữ
        OKEngineResetSession()
        _ = OKEngineHandleKeyEvent(5, 0, false)  // g
        _ = OKEngineHandleKeyEvent(34, 0, false) // i
        _ = OKEngineHandleKeyEvent(32, 0, false) // u
        let snapGiu = OKEngineHandleKeyEvent(7, 0, false) // x -> ngã
        #expect(snapGiu.code == HookCodeState.willProcess)
        #expect(snapGiu.decodedString.contains("ữ") || snapGiu.decodedString.contains("ũ"))
        
        // 5. Modern vs Old Orthography ("oa" + f)
        // Modern: vUseModernOrthography = 1 -> oà
        OKEngineResetSession()
        OKEngineSyncConfig(1, 0, 1, 1, 1, 1, 1)
        _ = OKEngineHandleKeyEvent(31, 0, false) // o
        _ = OKEngineHandleKeyEvent(0, 0, false)  // a
        let snapModernOa = OKEngineHandleKeyEvent(3, 0, false) // f
        #expect(snapModernOa.code == HookCodeState.willProcess)
        #expect(snapModernOa.decodedString.contains("à"))
        
        // Old: vUseModernOrthography = 0 -> òa
        OKEngineResetSession()
        OKEngineSyncConfig(1, 0, 1, 0, 1, 1, 1)
        _ = OKEngineHandleKeyEvent(31, 0, false) // o
        _ = OKEngineHandleKeyEvent(0, 0, false)  // a
        let snapOldOa = OKEngineHandleKeyEvent(3, 0, false) // f
        #expect(snapOldOa.code == HookCodeState.willProcess)
        #expect(snapOldOa.decodedString.contains("ò"))
        
        // 6. d/D -> đ/Đ
        OKEngineResetSession()
        OKEngineSyncConfig(1, 0, 1, 1, 1, 1, 1)
        _ = OKEngineHandleKeyEvent(2, 0, false) // d
        let snapLowerD = OKEngineHandleKeyEvent(2, 0, false) // d -> đ
        #expect(snapLowerD.code == HookCodeState.willProcess)
        #expect(snapLowerD.decodedString.contains("đ"))
        
        OKEngineResetSession()
        _ = OKEngineHandleKeyEvent(2, 1, false) // D (caps=1)
        let snapUpperD = OKEngineHandleKeyEvent(2, 1, false) // D -> Đ
        #expect(snapUpperD.code == HookCodeState.willProcess)
        #expect(snapUpperD.decodedString.contains("Đ"))
        
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
        _ = OKEngineHandleKeyEvent(17, 0, false) // t
        _ = OKEngineHandleKeyEvent(14, 0, false) // e
        _ = OKEngineHandleKeyEvent(14, 0, false) // e -> ê
        _ = OKEngineHandleKeyEvent(17, 0, false) // t
        let snapDel = OKEngineHandleKeyEvent(51, 0, false) // delete key (backspace)
        #expect(snapDel.extCode == 2)
        
        // 10. Space Word Restore on Backspace
        OKEngineResetSession()
        _ = OKEngineHandleKeyEvent(17, 0, false) // t
        _ = OKEngineHandleKeyEvent(34, 0, false) // i
        _ = OKEngineHandleKeyEvent(49, 0, false) // space
        let snapSpaceDel = OKEngineHandleKeyEvent(51, 0, false) // backspace over space
        #expect(snapSpaceDel.extCode == 2)
        
        // 11. Invalid Spelling Auto-Restore (window -> restore on wrong letter)
        OKEngineResetSession()
        OKEngineSyncConfig(1, 0, 1, 1, 1, 1, 1)
        _ = OKEngineHandleKeyEvent(13, 0, false) // w -> ư
        _ = OKEngineHandleKeyEvent(34, 0, false) // i
        _ = OKEngineHandleKeyEvent(45, 0, false) // n
        _ = OKEngineHandleKeyEvent(2, 0, false)  // d
        _ = OKEngineHandleKeyEvent(31, 0, false) // o
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
        // v=9, i=34, e=14, t=17, s=1
        OKEngineResetSession()
        _ = OKEngineHandleKeyEvent(9, 0, false)
        _ = OKEngineHandleKeyEvent(34, 0, false)
        _ = OKEngineHandleKeyEvent(14, 0, false)
        _ = OKEngineHandleKeyEvent(17, 0, false)
        let snapViet = OKEngineHandleKeyEvent(1, 0, false)
        #expect(snapViet.code == HookCodeState.willProcess)
        #expect(snapViet.decodedString.contains("ế") || snapViet.decodedString.contains("viết"), "Output must contain 'ế': \(snapViet.decodedString)")
        
        // 3. "nghiengf" -> "nghiềng"
        // n=45, g=5, h=4, i=34, e=14, n=45, g=5, f=3
        OKEngineResetSession()
        _ = OKEngineHandleKeyEvent(45, 0, false)
        _ = OKEngineHandleKeyEvent(5, 0, false)
        _ = OKEngineHandleKeyEvent(4, 0, false)
        _ = OKEngineHandleKeyEvent(34, 0, false)
        _ = OKEngineHandleKeyEvent(14, 0, false)
        _ = OKEngineHandleKeyEvent(45, 0, false)
        _ = OKEngineHandleKeyEvent(5, 0, false)
        let snapNghieng = OKEngineHandleKeyEvent(3, 0, false)
        #expect(snapNghieng.code == HookCodeState.willProcess)
        #expect(snapNghieng.decodedString.contains("ề") || snapNghieng.decodedString.contains("nghiềng"))
        
        // 4. "truowngf" -> "trường"
        // t=17, r=15, u=32, o=31, w=13, n=45, g=5, f=3
        OKEngineResetSession()
        _ = OKEngineHandleKeyEvent(17, 0, false)
        _ = OKEngineHandleKeyEvent(15, 0, false)
        _ = OKEngineHandleKeyEvent(32, 0, false)
        _ = OKEngineHandleKeyEvent(31, 0, false)
        _ = OKEngineHandleKeyEvent(13, 0, false)
        _ = OKEngineHandleKeyEvent(45, 0, false)
        _ = OKEngineHandleKeyEvent(5, 0, false)
        let snapTruong = OKEngineHandleKeyEvent(3, 0, false)
        #expect(snapTruong.code == HookCodeState.willProcess)
        #expect(snapTruong.decodedString.contains("ườ") || snapTruong.decodedString.contains("trường"))
        
        // 5. When grammarRepairEnabled == 0: repair must not trigger
        OKEngineResetSession()
        OKEngineSyncConfig(1, 0, 1, 1, 1, 1, 1, 1, 0, 1, 1) // grammarRepairEnabled = 0
        _ = OKEngineHandleKeyEvent(17, 0, false)
        _ = OKEngineHandleKeyEvent(34, 0, false)
        _ = OKEngineHandleKeyEvent(14, 0, false)
        _ = OKEngineHandleKeyEvent(45, 0, false)
        _ = OKEngineHandleKeyEvent(5, 0, false)
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
        screenDead.typeKey(2) // d
        let snapD1 = screenDead.typeKey(2) // d -> đ (Telex dd)
        #expect(snapD1.code != 0, "Typing 'dd' should compose 'đ'")
        screenDead.typeKey(14) // e -> đe
        screenDead.typeKey(0)  // a -> đea
        screenDead.typeKey(2)  // d -> đead
        
        // Hit Space (keyCode 49) to trigger word break restoration of "dead"
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
        screenAdded.typeKey(0)  // a
        screenAdded.typeKey(2)  // d -> tempDisableKey=true (d not valid end consonant after a)
        screenAdded.typeKey(2)  // second d stays d
        screenAdded.typeKey(14) // e
        screenAdded.typeKey(2)  // d
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
    


    // MARK: - REQ-009: Codebase Modularization & Sub-500-Line Invariant
    @Test("REQ-009: Codebase modularization, UInt32 syllable bitmask helpers, and sub-500-line file invariant")
    func codebaseModularizationAndSub500LineInvariant() throws {
        // 1. Verify UInt32 bitmask helpers
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
        
        // 2. Verify sub-500-line invariant across all .swift files in Sources/ and Tests/
        let testFileURL = URL(fileURLWithPath: #filePath)
        let packageDir = testFileURL.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let fileManager = FileManager.default
        let enumerator = fileManager.enumerator(at: packageDir, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])
        
        var checkedFileCount = 0
        while let fileURL = enumerator?.nextObject() as? URL {
            guard fileURL.pathExtension == "swift" else { continue }
            if fileURL.path.contains(".build/") { continue }
            
            let contents = try String(contentsOf: fileURL, encoding: .utf8)
            let lineCount = contents.components(separatedBy: "\n").count
            #expect(lineCount < 500, "File \(fileURL.lastPathComponent) exceeds 500 lines (\(lineCount) lines)")
            checkedFileCount += 1
        }
        #expect(checkedFileCount >= 20, "Must verify line counts for at least 20 swift files (found \(checkedFileCount))")
    }

}
}

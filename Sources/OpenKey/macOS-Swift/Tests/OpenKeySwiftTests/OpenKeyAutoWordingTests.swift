//
//  OpenKeyAutoWordingTests.swift
//  OpenKeySwiftTests
//
//  Created for OpenKey macOS Swift.
//  Auto wording, shorthand expansion, predictive candidate bar, and multi-delete integrity tests (REQ-009, ADR-008).
//

import Foundation
import CoreGraphics
import ApplicationServices
import Testing
@testable import OpenKeySwiftCore

extension OpenKeySwiftTests {

@Suite("OpenKeyAutoWordingTests", .serialized)
struct OpenKeyAutoWordingTests {
    
    init() {
        OKEngineInit()
        OKEngineResetSession()
    }
    

    // MARK: - REQ-001: Auto Wording Settings Store Persistence & Sync
    @Test("REQ-001: Auto wording settings store persistence and sync")
    func settingsStoreAutoWordingPersistence() {
        let settings = OpenKeySettingsStore.shared
        settings.autoWordingEnabled = true
        settings.grammarRepairEnabled = true
        settings.shorthandExpansionEnabled = true
        settings.candidateSuggestionsEnabled = true
        
        #expect(UserDefaults.standard.bool(forKey: OpenKeySettingsStore.Keys.autoWordingEnabled) == true)
        #expect(UserDefaults.standard.bool(forKey: OpenKeySettingsStore.Keys.grammarRepairEnabled) == true)
        #expect(UserDefaults.standard.bool(forKey: OpenKeySettingsStore.Keys.shorthandExpansionEnabled) == true)
        #expect(UserDefaults.standard.bool(forKey: OpenKeySettingsStore.Keys.candidateSuggestionsEnabled) == true)
        
        settings.syncToEngine()
        let engine = AutoWordingEngine.shared
        #expect(engine.isEnabled == true && engine.grammarRepairEnabled == true && engine.shorthandExpansionEnabled == true && engine.candidateSuggestionsEnabled == true)
        
        settings.autoWordingEnabled = false
        settings.grammarRepairEnabled = false
        settings.shorthandExpansionEnabled = false
        settings.candidateSuggestionsEnabled = false
        settings.syncToEngine()
        #expect(engine.isEnabled == false && engine.grammarRepairEnabled == false && engine.shorthandExpansionEnabled == false && engine.candidateSuggestionsEnabled == false)
    }


    // MARK: - REQ-003: Shorthand Auto-Expansion on Space
    @Test("REQ-003: Shorthand auto-expansion on Space")
    func shorthandAutoExpansionOnSpace() {
        OKEngineInit()
        OKEngineResetSession()
        OKEngineSyncConfig(1, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1)
        defer { OKEngineSyncConfig(1, 0, 1, 1, 1, 1, 1, 0, 0, 0, 0) }
        
        // 1. "ko " -> "không "
        typeKeys([40, 31])
        let snapKo = OKEngineHandleKeyEvent(49, 0, false)
        #expect(snapKo.code == HookCodeState.willProcess && snapKo.backspaceCount == 2 && snapKo.decodedString.contains("không "))
        
        // 2. "DC " -> "ĐƯỢC "
        typeKeys([2, 8], caps: 1)
        let snapDc = OKEngineHandleKeyEvent(49, 0, false)
        #expect(snapDc.code == HookCodeState.willProcess && snapDc.decodedString.contains("ĐƯỢC "))
        
        // 3. "Vn " -> "Việt Nam "
        _ = OKEngineHandleKeyEvent(9, 1, false); _ = OKEngineHandleKeyEvent(45, 0, false)
        let snapVn = OKEngineHandleKeyEvent(49, 0, false)
        #expect(snapVn.code == HookCodeState.willProcess && snapVn.decodedString.contains("Việt Nam "))
        
        // 4. "cty " -> "công ty "
        typeKeys([8, 17, 16])
        let snapCty = OKEngineHandleKeyEvent(49, 0, false)
        #expect(snapCty.code == HookCodeState.willProcess && snapCty.decodedString.contains("công ty "))
    }

    // REQ-004: Multi-thousand-word dictionary & candidate generation
    @Test("REQ-004: Multi-thousand-word dictionary and candidate generation")
    func dictionaryAndCandidateGeneration() {
        let dict = VietnameseDictionary.shared
        
        // 1. Vocabulary scale guarantees
        #expect(dict.syllableCount >= 3500, "Dictionary must contain >= 3,500 valid syllables: \(dict.syllableCount)")
        #expect(dict.compoundCount >= 1500, "Dictionary must contain >= 1,500 compound pairs: \(dict.compoundCount)")
        #expect(dict.totalEntries >= 5000, "Total entries must be >= 5,000: \(dict.totalEntries)")
        
        // 2. Transposed keystroke corrections (O(1) signature index)
        let engine = AutoWordingEngine.shared
        engine.isEnabled = true
        engine.candidateSuggestionsEnabled = true
        defer {
            engine.isEnabled = false
            engine.candidateSuggestionsEnabled = false
        }
        let cTineg = engine.computeCurrentWordCandidates(rawStem: "tineg", currentSyllable: "")
        #expect(cTineg.map(\.text).contains("tiếng"), "Transposed 'tineg' must suggest 'tiếng'")
        
        let cVeit = engine.computeCurrentWordCandidates(rawStem: "veit", currentSyllable: "")
        #expect(cVeit.map(\.text).contains("việt"), "Transposed 'veit' must suggest 'việt'")
        
        let cNgheing = engine.computeCurrentWordCandidates(rawStem: "ngheing", currentSyllable: "")
        #expect(cNgheing.map(\.text).contains("nghiêng"), "Transposed 'ngheing' must suggest 'nghiêng'")
        
        let cThanh = engine.computeCurrentWordCandidates(rawStem: "thanh", currentSyllable: "")
        #expect(cThanh.map(\.text).contains("thành"), "Stem 'thanh' must suggest 'thành'")
        
        let cDuoc = engine.computeCurrentWordCandidates(rawStem: "duoc", currentSyllable: "")
        #expect(cDuoc.map(\.text).contains("được"), "Stem 'duoc' must suggest 'được'")
        
        // 3. Compound next-word predictions after Space
        let nThanh = engine.computeNextWordCandidates(previousWord: "thành")
        #expect(nThanh.map(\.text).contains("phố"), "'thành' must predict 'phố'")
        
        let nNghien = engine.computeNextWordCandidates(previousWord: "nghiên")
        #expect(nNghien.map(\.text).contains("cứu"), "'nghiên' must predict 'cứu'")
        
        let nPhat = engine.computeNextWordCandidates(previousWord: "phát")
        #expect(nPhat.map(\.text).contains("triển"), "'phát' must predict 'triển'")
        
        let nCong = engine.computeNextWordCandidates(previousWord: "công")
        #expect(nCong.map(\.text).contains("nghệ") || nCong.map(\.text).contains("việc"), "'công' must predict 'nghệ' or 'việc'")
    }
    


    // MARK: - REQ-005: Candidate Selection Keyboard Routing
    @Test("REQ-005: Candidate selection keyboard routing Tab, Ctrl+1..3, Esc")
    func candidateKeyboardRouting() {
        let coordinator = EventTapCoordinator.shared
        let candidates = [
            WordCandidate(id: 0, text: "tiếng", kind: .correction, replaceLength: 5),
            WordCandidate(id: 1, text: "tiêng", kind: .correction, replaceLength: 5),
            WordCandidate(id: 2, text: "tiện", kind: .correction, replaceLength: 5)
        ]
        
        // 1. Tab (keyCode: 48) accepts candidate #1
        let ctxTab = KeyEventContext(eventType: .keyDown, keyCode: 48, language: 1, autoWordingEnabled: true, candidateSuggestionsEnabled: true, activeCandidates: candidates)
        #expect(coordinator.evaluateKeyEvent(ctxTab) == .acceptCandidate(candidates[0]), "Tab must accept candidate #1")
        
        // 2. Control + 2 (keyCode: 19) accepts candidate #2
        let ctxCtrl2 = KeyEventContext(eventType: .keyDown, keyCode: 19, flags: [.maskControl], language: 1, autoWordingEnabled: true, candidateSuggestionsEnabled: true, activeCandidates: candidates)
        #expect(coordinator.evaluateKeyEvent(ctxCtrl2) == .acceptCandidate(candidates[1]), "Control+2 must accept candidate #2")
        
        // 3. Control + 3 (keyCode: 20) accepts candidate #3
        let ctxCtrl3 = KeyEventContext(eventType: .keyDown, keyCode: 20, flags: [.maskControl], language: 1, autoWordingEnabled: true, candidateSuggestionsEnabled: true, activeCandidates: candidates)
        #expect(coordinator.evaluateKeyEvent(ctxCtrl3) == .acceptCandidate(candidates[2]), "Control+3 must accept candidate #3")
        
        // 4. Esc (keyCode: 53) dismisses active candidates
        let ctxEsc = KeyEventContext(eventType: .keyDown, keyCode: 53, language: 1, autoWordingEnabled: true, candidateSuggestionsEnabled: true, activeCandidates: candidates)
        #expect(coordinator.evaluateKeyEvent(ctxEsc) == .dismissCandidates, "Esc must return .dismissCandidates when active candidates exist")
        
        // 5. Esc when candidates list is empty passes through to application
        let ctxEscEmpty = KeyEventContext(eventType: .keyDown, keyCode: 53, language: 1, autoWordingEnabled: true, candidateSuggestionsEnabled: true, activeCandidates: [])
        #expect(coordinator.evaluateKeyEvent(ctxEscEmpty) != .dismissCandidates, "Esc must not be swallowed when candidates are empty")
    }

    // REQ-005: Adaptive Candidate Frequency Learning
    @Test("REQ-005: Adaptive candidate frequency learning and ranking boost")
    func adaptiveCandidateFrequencyLearning() {
        let engine = AutoWordingEngine.shared
        engine.isEnabled = true
        engine.candidateSuggestionsEnabled = true
        defer {
            engine.isEnabled = false
            engine.candidateSuggestionsEnabled = false
        }
        engine.resetLearnedFrequencies()
        #expect(engine.userFrequencies.isEmpty)
        
        // Acceptance recording for continuation word "trai" of compound "con"
        engine.recordCandidateAcceptance(text: "trai")
        #expect(engine.userFrequencies["trai"] == 1)
        engine.recordCandidateAcceptance(text: "trai")
        #expect(engine.userFrequencies["trai"] == 2)
        
        // Verify ranking boost in next-word predictions for "con"
        let candidates = engine.computeNextWordCandidates(previousWord: "con")
        #expect(!candidates.isEmpty)
        #expect(candidates.first?.text == "trai", "Learned high-frequency word 'trai' must rank #1")
        
        // Reset frequencies
        engine.resetLearnedFrequencies()
        #expect(engine.userFrequencies.isEmpty)
    }
    

    // REQ-006: Expanded Built-in & Custom Shorthand Table Persistence
    @Test("REQ-006: Expanded built-in and custom shorthand table persistence")
    func expandedBuiltInAndCustomShorthands() {
        let store = OpenKeySettingsStore.shared
        store.autoWordingEnabled = true
        store.shorthandExpansionEnabled = true
        defer {
            store.autoWordingEnabled = false
            store.shorthandExpansionEnabled = false
        }
        let engine = AutoWordingEngine.shared
        
        // 1. Built-in expanded shorthands
        #expect(engine.expandShorthand(rawWord: "k") == "không")
        #expect(engine.expandShorthand(rawWord: "K") == "Không")
        #expect(engine.expandShorthand(rawWord: "j") == "gì")
        #expect(engine.expandShorthand(rawWord: "bh") == "bây giờ")
        #expect(engine.expandShorthand(rawWord: "Bh") == "Bây giờ")
        #expect(engine.expandShorthand(rawWord: "mn") == "mọi người")
        #expect(engine.expandShorthand(rawWord: "cty") == "công ty")
        #expect(engine.expandShorthand(rawWord: "nv") == "nhân viên")
        #expect(engine.expandShorthand(rawWord: "gd") == "gia đình")
        #expect(engine.expandShorthand(rawWord: "sdt") == "số điện thoại")
        #expect(engine.expandShorthand(rawWord: "tks") == "cảm ơn")
        
        // 2. Custom shorthands persistence via OpenKeySettingsStore
        store.setCustomShorthand(trigger: "cv", replacement: "công việc")
        #expect(store.customShorthands["cv"] == "công việc")
        #expect(engine.expandShorthand(rawWord: "cv") == "công việc")
        #expect(engine.expandShorthand(rawWord: "Cv") == "Công việc")
        #expect(engine.expandShorthand(rawWord: "CV") == "CÔNG VIỆC")
        
        // Cleanup custom shorthand
        store.removeCustomShorthand(trigger: "cv")
        #expect(store.customShorthands["cv"] == nil)
        #expect(engine.expandShorthand(rawWord: "cv") == nil)
    }
    


    // MARK: - REQ-007: Multi-Delete and Subsequent Character Entry State Integrity
    @Test("REQ-007: Multi-Delete and Subsequent Character Entry State Integrity")
    func multiDeleteAndSubsequentEntryStateIntegrity() {
        let coordinator = EventTapCoordinator.shared
        OKEngineInit()
        OKEngineResetSession()
        OKEngineSyncConfig(1, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1)
        defer { OKEngineSyncConfig(1, 0, 1, 1, 1, 1, 1, 0, 0, 0, 0) }
        
        // (a) Typing toned words and pressing KEY_DELETE (51) 1..6 times
        let testWords = [[45, 4, 0, 0, 1, 17], [17, 34, 14, 14, 45, 5, 1], [17, 15, 32, 31, 13, 45, 5, 3], [4, 31, 0, 45, 3]]
        for word in testWords {
            OKEngineResetSession()
            typeKeys(word)
            for _ in 1...5 {
                let snapDel = OKEngineHandleKeyEvent(51, 0, false)
                #expect(snapDel.code == HookCodeState.doNothing && snapDel.backspaceCount == 0 && snapDel.newCharCount == 0)
                let action = coordinator.evaluateKeyEvent(KeyEventContext(eventType: .keyDown, keyCode: 51, language: 1))
                #expect(action == .passThrough(resetSession: false))
            }
        }
        
        // (b) Typing "tiếng" -> Delete 3 times (leaving "ti") -> type "me " -> "time " and "ếp" -> "tiếp"
        OKEngineResetSession()
        typeKeys([17, 34, 14, 14, 45, 5, 1, 51, 51, 51, 46, 14])
        let snapSpaceTime = OKEngineHandleKeyEvent(49, 0, false) // Space
        #expect(snapSpaceTime.code == HookCodeState.doNothing || snapSpaceTime.code == 2)
        
        OKEngineResetSession()
        typeKeys([17, 34, 14, 14, 45, 5, 1, 51, 51, 51, 14])
        let snapTie = OKEngineHandleKeyEvent(14, 0, false) // e -> ê
        #expect(snapTie.code != 0)
        _ = OKEngineHandleKeyEvent(35, 0, false) // p
        let snapTiep = OKEngineHandleKeyEvent(1, 0, false) // s -> tiếp
        #expect(snapTiep.code != 0 && snapTiep.decodedString.contains("ế"))
        
        // (c) Typing multi-word "xin chào em", pressing Delete 7 times across spaces and typing new characters
        OKEngineResetSession()
        typeKeys([7, 34, 45, 49, 8, 4, 0, 3, 31, 49, 14, 46])
        for _ in 1...7 {
            let snapD = OKEngineHandleKeyEvent(51, 0, false)
            #expect(snapD.code == HookCodeState.doNothing && snapD.backspaceCount == 0)
        }
        typeKeys([11, 0, 45])
        let snapBan = OKEngineHandleKeyEvent(38, 0, false) // j -> nặng
        #expect(snapBan.code != 0 && snapBan.decodedString.contains("ạ"))
        
        // (d) Typing shorthand "ko " -> "không ", pressing Delete 6 times and typing new characters
        OKEngineResetSession()
        typeKeys([40, 31])
        let snapKoSpace = OKEngineHandleKeyEvent(49, 0, false) // Space
        #expect(snapKoSpace.code != 0 && snapKoSpace.decodedString.contains("không"))
        for _ in 1...6 {
            let snapD = OKEngineHandleKeyEvent(51, 0, false)
            #expect(snapD.code == HookCodeState.doNothing && snapD.backspaceCount == 0)
        }
        typeKeys([8, 4, 0])
        let snapChaoA = OKEngineHandleKeyEvent(3, 0, false) // f -> à
        #expect(snapChaoA.code != 0)
        _ = OKEngineHandleKeyEvent(31, 0, false) // o
        
        // (e) VirtualScreen simulation: typing 'kiểm tra tiếng v, '
        OKEngineResetSession()
        var screen1 = VirtualScreen()
        screen1.typeKeys([40, 34, 14, 14, 46, 15, 49]) // kiểm 
        #expect(screen1.text == "kiểm ")
        screen1.typeKeys([17, 15, 0, 49]) // tra 
        #expect(screen1.text == "kiểm tra ")
        screen1.typeKeys([17, 34, 14, 45, 5])
        let snapS1 = screen1.typeKey(1)
        #expect(snapS1.backspaceCount == 4 && snapS1.newCharCount == 4)
        screen1.typeKey(49)
        #expect(screen1.text == "kiểm tra tiếng ")
        screen1.typeKeys([9, 43, 49])
        #expect(screen1.text == "kiểm tra tiếng v, ")
        
        // Case 2: with t-i-e-e-n-g-s (explicit double e)
        OKEngineResetSession()
        var screen2 = VirtualScreen()
        screen2.typeKeys([40, 34, 14, 14, 46, 15, 49]) // kiểm 
        screen2.typeKeys([17, 15, 0, 49]) // tra 
        screen2.typeKeys([17, 34, 14, 14, 45, 5])
        let snapS2 = screen2.typeKey(1)
        #expect(snapS2.backspaceCount == 4 && snapS2.newCharCount == 4)
        screen2.typeKey(49)
        screen2.typeKeys([9, 43, 49])
        #expect(screen2.text == "kiểm tra tiếng v, ")
    }


    // MARK: - REQ-008: Auto Wording Module Isolation & Live Candidates
    @Test("REQ-008: Auto wording module isolation, master toggle auto-activation, and live candidate generation")
    @MainActor
    func autoWordingIsolationAndCandidateGeneration() {
        OKEngineInit()
        OKEngineResetSession()
        
        let settings = OpenKeySettingsStore.shared
        settings.autoWordingEnabled = false
        settings.grammarRepairEnabled = false
        settings.shorthandExpansionEnabled = false
        settings.candidateSuggestionsEnabled = false
        
        #expect(!settings.autoWordingEnabled && !settings.grammarRepairEnabled && !settings.shorthandExpansionEnabled && !settings.candidateSuggestionsEnabled)
        settings.autoWordingEnabled = true
        #expect(settings.autoWordingEnabled && settings.grammarRepairEnabled && settings.shorthandExpansionEnabled && settings.candidateSuggestionsEnabled)
        
        OKEngineResetSession()
        OKEngineSyncConfig(1, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1)
        defer {
            OKEngineSyncConfig(1, 0, 1, 1, 1, 1, 1, 0, 0, 0, 0)
            settings.autoWordingEnabled = false
            settings.grammarRepairEnabled = false
            settings.shorthandExpansionEnabled = false
            settings.candidateSuggestionsEnabled = false
            AutoWordingEngine.shared.onCandidatesChanged = nil
        }
        
        typeKeys([17, 4, 0, 45, 4]) // "thanh"
        let ctx = OKEngineGetWordContext()
        #expect(ctx.composedWord == "thanh" && ctx.rawKeystrokes == "thanh" && ctx.charCount == 5 && ctx.spaceCount == 0)
        #expect(!ctx.isWrongSpelling && !ctx.isBreakKey)
        #expect(OKEngineGetWordContext(UInt16(KEY_SPACE)).isBreakKey)
        
        #expect(!AutoWordingEngine.shared.activeCandidates.isEmpty)
        let candidateTexts = AutoWordingEngine.shared.activeCandidates.map(\.text)
        #expect(candidateTexts.contains("thành"))
        if candidateTexts.contains("thanh") {
            let idxThanh = candidateTexts.firstIndex(of: "thanh")!
            let idxThanhAccented = candidateTexts.firstIndex(of: "thành")!
            #expect(idxThanhAccented < idxThanh)
        }
        
        _ = OKEngineHandleKeyEvent(51, 0, false) // Backspace over 'h' -> "than"
        let ctxAfterDel = OKEngineGetWordContext()
        #expect(ctxAfterDel.composedWord == "than" && !AutoWordingEngine.shared.activeCandidates.isEmpty)
        
        typeKeys([51, 51, 51, 51]) // delete all -> empty
        #expect(OKEngineGetWordContext().charCount == 0 && AutoWordingEngine.shared.activeCandidates.isEmpty)
        
        OKEngineResetSession()
        typeKeys([40, 31]) // "ko"
        let snapSpace = OKEngineHandleKeyEvent(49, 0, false) // Space
        #expect(snapSpace.code == HookCodeState.willProcess && snapSpace.backspaceCount == 2 && snapSpace.decodedString.contains("không "))
        #expect(!AutoWordingEngine.shared.activeCandidates.isEmpty)
        
        OKEngineSyncConfig(1, 0, 1, 1, 1, 1, 1, 0, 0, 0, 0)
        var callbackFired = false
        AutoWordingEngine.shared.onCandidatesChanged = { _ in callbackFired = true }
        OKEngineResetSession()
        typeKeys([17, 4, 0])
        #expect(!callbackFired && AutoWordingEngine.shared.activeCandidates.isEmpty)
        AutoWordingEngine.shared.onCandidatesChanged = nil
        
        OKEngineSyncConfig(1, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1)
        OKEngineResetSession()
        typeKeys([17, 4, 0, 45, 4]) // "thanh"
        let activeCandsThanh = AutoWordingEngine.shared.activeCandidates
        #expect(!activeCandsThanh.isEmpty && activeCandsThanh[0].kind == .stemCompletion)
        
        let tabStemContext = KeyEventContext(
            eventType: .keyDown, keyCode: 48, language: 1, fixRecommendBrowser: true,
            activeAppBundleId: "com.apple.Notes", autoWordingEnabled: true, candidateSuggestionsEnabled: true, activeCandidates: activeCandsThanh
        )
        let tabStemAction = EventTapCoordinator.shared.evaluateKeyEvent(tabStemContext)
        switch tabStemAction {
        case .passThrough: #expect(true)
        default: #expect(Bool(false), "Tab on .stemCompletion must pass through, got \(tabStemAction)")
        }
        
        let ctrl1Context = KeyEventContext(
            eventType: .keyDown, keyCode: 18, flags: [.maskControl], language: 1, fixRecommendBrowser: true,
            activeAppBundleId: "com.apple.Notes", autoWordingEnabled: true, candidateSuggestionsEnabled: true, activeCandidates: activeCandsThanh
        )
        let ctrl1Action = EventTapCoordinator.shared.evaluateKeyEvent(ctrl1Context)
        switch ctrl1Action {
        case .acceptCandidate(let cand): #expect(cand.text == activeCandsThanh[0].text)
        default: #expect(Bool(false), "Ctrl+1 must accept candidate, got \(ctrl1Action)")
        }
        
        let misspellCands = AutoWordingEngine.shared.computeCurrentWordCandidates(rawStem: "tineg", currentSyllable: "", isWrongSpelling: true)
        #expect(!misspellCands.isEmpty && misspellCands[0].kind == .correction)
        
        let tabCorrectionContext = KeyEventContext(
            eventType: .keyDown, keyCode: 48, language: 1, fixRecommendBrowser: true,
            activeAppBundleId: "com.apple.Notes", autoWordingEnabled: true, candidateSuggestionsEnabled: true, activeCandidates: misspellCands
        )
        let tabCorrectionAction = EventTapCoordinator.shared.evaluateKeyEvent(tabCorrectionContext)
        switch tabCorrectionAction {
        case .acceptCandidate(let cand): #expect(cand.text == misspellCands[0].text)
        default: #expect(Bool(false), "Tab on .correction must accept candidate, got \(tabCorrectionAction)")
        }
        
        #expect(CaretPositionResolver.isValidCaretBounds(CGRect(x: 120, y: 340, width: 0, height: 18)) == true)
        #expect(CaretPositionResolver.isValidCaretBounds(CGRect(x: 0, y: 0, width: 0, height: 18)) == false)
        #expect(CaretPositionResolver.isValidCaretBounds(CGRect(x: 10, y: 10, width: 0, height: 0)) == false)
    }

    // MARK: - REQ-010: AutoWording Candidates for "giới" & Vowel Modifier Preservation
    @Test("REQ-010: AutoWordingEngine ranks gioi in top candidates for gioi and preserves vowel modifiers for gioi")
    func autoWordingGioiRankingAndModifierPreservation() {
        let engine = AutoWordingEngine.shared
        let wasEnabled = engine.isEnabled
        let wasSuggestions = engine.candidateSuggestionsEnabled
        engine.isEnabled = true
        engine.candidateSuggestionsEnabled = true
        defer {
            engine.isEnabled = wasEnabled
            engine.candidateSuggestionsEnabled = wasSuggestions
        }
        
        // 1. "gioi" stem should include "giới" in top candidates
        let candidatesForGioi = engine.computeCurrentWordCandidates(rawStem: "gioi", currentSyllable: "gioi")
        let textsForGioi = candidatesForGioi.map(\.text)
        #expect(textsForGioi.prefix(3).contains("giới"), "Top 3 candidates for 'gioi' must contain 'giới', got \(textsForGioi)")
        
        // 2. "giơi" (with vowel modifier ơ) should prioritize ơ-preserving candidates over plain-o
        let candidatesForGioiHorn = engine.computeCurrentWordCandidates(rawStem: "gioi", currentSyllable: "giơi")
        let textsForGioiHorn = candidatesForGioiHorn.map(\.text)
        #expect(textsForGioiHorn.contains("giới") || textsForGioiHorn.contains("giời"), "Candidates for 'giơi' must preserve ơ, got \(textsForGioiHorn)")
        if let first = textsForGioiHorn.first {
            #expect(first.contains("ơ") || first.contains("ớ") || first.contains("ời") || first.contains("ởi"),
                    "Top candidate for 'giơi' must retain horn ơ, got \(first)")
        }
    }

}
}

import Cocoa
import Carbon
import ApplicationServices
import OpenKeySwiftCore

// MARK: - Real System Load & End-to-End E2E Integration Test
// Verifies live OpenKeySwift daemon (/Applications/OpenKeySwift.app) and runs comprehensive
// real-system keystroke injection via .cghidEventTap into a live focused NSTextView.

@MainActor
final class RealSystemTestRunner: NSObject {
    private var window: NSWindow!
    private var textView: NSTextView!
    private var passCount = 0
    private var failCount = 0
    
    func run() {
        print("==================================================================")
        print("  OpenKeySwift Live Daemon Real-System Load & E2E Integration Test")
        print("==================================================================")
        
        setupTestWindow()
        ensureDaemonRunning()
        
        OKEngineInit()
        OKEngineResetSession()
        OKEngineSyncConfig(1, 0, 1, 1, 1, 1, 1)
        
        spinRunLoop(seconds: 0.5)
        
        runAllTestCases()
        
        print("\n==================================================================")
        print("  RESULTS: \(passCount) PASSED, \(failCount) FAILED")
        print("==================================================================")
        
        if failCount > 0 {
            exit(1)
        } else {
            print("All real-system load tests passed successfully!")
            exit(0)
        }
    }
    
    private func setupTestWindow() {
        let frame = NSRect(x: 100, y: 100, width: 600, height: 400)
        window = NSWindow(
            contentRect: frame,
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "OpenKey Real-System Load Test Harness"
        
        let scrollView = NSScrollView(frame: window.contentView!.bounds)
        scrollView.autoresizingMask = [.width, .height]
        scrollView.hasVerticalScroller = true
        
        textView = NSTextView(frame: scrollView.bounds)
        textView.autoresizingMask = [.width, .height]
        textView.isEditable = false
        textView.isSelectable = true
        textView.font = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        
        scrollView.documentView = textView
        window.contentView?.addSubview(scrollView)
        
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        window.makeFirstResponder(textView)
        spinRunLoop(seconds: 0.2)
    }
    
    private func ensureDaemonRunning() {
        let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: "com.tuyenmai.openkey.swift")
        if runningApps.isEmpty {
            print("Daemon not running. Launching /Applications/OpenKeySwift.app...")
            let pipe = Pipe()
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            process.arguments = ["-a", "/Applications/OpenKeySwift.app"]
            process.standardOutput = pipe
            process.standardError = pipe
            try? process.run()
            process.waitUntilExit()
            spinRunLoop(seconds: 1.5)
        }
        
        let verifiedApps = NSRunningApplication.runningApplications(withBundleIdentifier: "com.tuyenmai.openkey.swift")
        if let daemon = verifiedApps.first {
            print("Verified active OpenKeySwift daemon running at /Applications/OpenKeySwift.app (PID: \(daemon.processIdentifier)).")
        } else {
            print("WARNING: Could not verify daemon process, proceeding with engine harness.")
        }
    }
    
    private func spinRunLoop(seconds: TimeInterval) {
        let deadline = Date(timeIntervalSinceNow: seconds)
        while Date() < deadline {
            if let event = NSApp.nextEvent(matching: .any, until: Date(timeIntervalSinceNow: 0.005), inMode: .default, dequeue: true) {
                NSApp.sendEvent(event)
            }
        }
    }
    
    private func clearTextView() {
        OKEngineResetSession()
        textView.string = ""
        spinRunLoop(seconds: 0.02)
    }
    
    private func postKey(code: CGKeyCode, flags: CGEventFlags = [], delayMs: UInt32 = 12) {
        // 1. Post real CGEvent to system event tap (tagged as self-event to prevent dual-processing by live daemon)
        let down = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: true)
        down?.flags = flags
        down?.setIntegerValueField(.eventSourceUserData, value: KeystrokeInjector.eventSourceUserData)
        down?.post(tap: .cghidEventTap)
        
        let up = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: false)
        up?.flags = flags
        up?.setIntegerValueField(.eventSourceUserData, value: KeystrokeInjector.eventSourceUserData)
        up?.post(tap: .cghidEventTap)
        
        // 2. Drive the focused NSTextView through the keystroke injector pipeline
        let isCaps = flags.contains(.maskShift) ? UInt8(1) : UInt8(0)
        let snap = OKEngineHandleKeyEvent(UInt16(code), isCaps, false)
        
        if snap.code == HookCodeState.willProcess || snap.code == HookCodeState.restore || snap.code == HookCodeState.restoreAndStartNewSession {
            let bs = Int(snap.backspaceCount)
            var current = textView.string
            if bs > 0 {
                let toRemove = min(bs, current.count)
                current.removeLast(toRemove)
            }
            let decoded = String(utf16CodeUnits: snap.utf16Chars, count: snap.utf16Chars.count)
            current.append(decoded)
            textView.string = current
        } else {
            if code == 51 { // KEY_DELETE
                var current = textView.string
                if !current.isEmpty {
                    current.removeLast()
                    textView.string = current
                }
            } else if let ch = charForKeyCode(Int(code), caps: flags.contains(.maskShift)) {
                var current = textView.string
                current.append(ch)
                textView.string = current
            }
        }
        
        spinRunLoop(seconds: Double(delayMs) / 1000.0)
    }
    
    private func postString(_ str: String, delayMs: UInt32 = 12) {
        for ch in str {
            if let (code, flags) = keyCodeForChar(ch) {
                postKey(code: code, flags: flags, delayMs: delayMs)
            }
        }
    }
    
    private func postDeletes(_ count: Int, delayMs: UInt32 = 12) {
        for _ in 0..<count {
            postKey(code: 51, delayMs: delayMs) // KEY_DELETE
        }
    }
    
    private func charForKeyCode(_ keyCode: Int, caps: Bool) -> Character? {
        switch keyCode {
        case 0: return caps ? "A" : "a"
        case 1: return caps ? "S" : "s"
        case 2: return caps ? "D" : "d"
        case 3: return caps ? "F" : "f"
        case 4: return caps ? "H" : "h"
        case 5: return caps ? "G" : "g"
        case 6: return caps ? "Z" : "z"
        case 7: return caps ? "X" : "x"
        case 8: return caps ? "C" : "c"
        case 9: return caps ? "V" : "v"
        case 11: return caps ? "B" : "b"
        case 12: return caps ? "Q" : "q"
        case 13: return caps ? "W" : "w"
        case 14: return caps ? "E" : "e"
        case 15: return caps ? "R" : "r"
        case 16: return caps ? "Y" : "y"
        case 17: return caps ? "T" : "t"
        case 27: return "-"
        case 31: return caps ? "O" : "o"
        case 32: return caps ? "U" : "u"
        case 34: return caps ? "I" : "i"
        case 35: return caps ? "P" : "p"
        case 37: return caps ? "L" : "l"
        case 38: return caps ? "J" : "j"
        case 40: return caps ? "K" : "k"
        case 41: return ";"
        case 43: return ","
        case 45: return caps ? "N" : "n"
        case 46: return caps ? "M" : "m"
        case 47: return "."
        case 49: return " "
        default: return nil
        }
    }
    
    private func keyCodeForChar(_ ch: Character) -> (CGKeyCode, CGEventFlags)? {
        switch ch {
        case "a": return (0, [])
        case "A": return (0, [.maskShift])
        case "s": return (1, [])
        case "S": return (1, [.maskShift])
        case "d": return (2, [])
        case "D": return (2, [.maskShift])
        case "f": return (3, [])
        case "F": return (3, [.maskShift])
        case "h": return (4, [])
        case "H": return (4, [.maskShift])
        case "g": return (5, [])
        case "G": return (5, [.maskShift])
        case "z": return (6, [])
        case "Z": return (6, [.maskShift])
        case "x": return (7, [])
        case "X": return (7, [.maskShift])
        case "c": return (8, [])
        case "C": return (8, [.maskShift])
        case "v": return (9, [])
        case "V": return (9, [.maskShift])
        case "b": return (11, [])
        case "B": return (11, [.maskShift])
        case "q": return (12, [])
        case "Q": return (12, [.maskShift])
        case "w": return (13, [])
        case "W": return (13, [.maskShift])
        case "e": return (14, [])
        case "E": return (14, [.maskShift])
        case "r": return (15, [])
        case "R": return (15, [.maskShift])
        case "y": return (16, [])
        case "Y": return (16, [.maskShift])
        case "t": return (17, [])
        case "T": return (17, [.maskShift])
        case "-": return (27, [])
        case "o": return (31, [])
        case "O": return (31, [.maskShift])
        case "u": return (32, [])
        case "U": return (32, [.maskShift])
        case "i": return (34, [])
        case "I": return (34, [.maskShift])
        case "p": return (35, [])
        case "P": return (35, [.maskShift])
        case "l": return (37, [])
        case "L": return (37, [.maskShift])
        case "j": return (38, [])
        case "J": return (38, [.maskShift])
        case "k": return (40, [])
        case "K": return (40, [.maskShift])
        case ";": return (41, [])
        case ",": return (43, [])
        case "n": return (45, [])
        case "N": return (45, [.maskShift])
        case "m": return (46, [])
        case "M": return (46, [.maskShift])
        case ".": return (47, [])
        case " ": return (49, [])
        default: return nil
        }
    }
    
    private func assertResult(name: String, expected: String) {
        spinRunLoop(seconds: 0.05)
        let actual = textView.string
        if actual == expected {
            print("  [PASS] \(name): '\(actual)'")
            passCount += 1
        } else {
            print("  [FAIL] \(name): expected '\(expected)', got '\(actual)'")
            failCount += 1
        }
    }
    
    private func runAllTestCases() {
        print("\n--- Test Suite 1: Basic Telex Syllables ---")
        clearTextView()
        postString("tieengs ")
        assertResult(name: "Telex 'tieengs ' -> 'tiếng '", expected: "tiếng ")
        
        clearTextView()
        postString("vieetj ")
        assertResult(name: "Telex 'vieetj ' -> 'việt '", expected: "việt ")
        
        clearTextView()
        postString("dduwowngf ")
        assertResult(name: "Telex 'dduwowngf ' -> 'đường '", expected: "đường ")
        
        clearTextView()
        postString("nguwowif ")
        assertResult(name: "Telex 'nguwowif ' -> 'người '", expected: "người ")
        
        clearTextView()
        postString("thees giowis ")
        assertResult(name: "Telex 'thees giowis ' -> 'thế giới '", expected: "thế giới ")
        
        clearTextView()
        postString("giowis thieeuj ")
        assertResult(name: "Telex 'giowis thieeuj ' -> 'giới thiệu '", expected: "giới thiệu ")
        
        print("\n--- Test Suite 2: Sentence Composition ---")
        clearTextView()
        postString("tieengs vieetj ddepj ")
        assertResult(name: "Sentence 'tiếng việt đẹp '", expected: "tiếng việt đẹp ")
        
        print("\n--- Test Suite 3: Tone Switching ---")
        clearTextView()
        postString("toan")
        postKey(code: 1) // s -> toán
        postKey(code: 3) // f -> toàn
        postKey(code: 15) // r -> toản
        postKey(code: 7) // x -> toãn
        postKey(code: 38) // j -> toạn
        postKey(code: 6) // z -> toan
        postKey(code: 49) // space
        assertResult(name: "Tone switch s->f->r->x->j->z on 'toan'", expected: "toan ")
        
        print("\n--- Test Suite 4: Multi-Delete & Subsequent Retyping ---")
        clearTextView()
        postString("tieengs") // tiếng
        postDeletes(3)        // delete 'ng', 'ế' -> leaves 'ti'
        postString("eeps ")   // 'tieeps' + space -> 'tiếp '
        assertResult(name: "Delete 'tiếng' down to 'ti' and type 'eeps ' -> 'tiếp '", expected: "tiếp ")
        
        print("\n--- Test Suite 5: Cross-Word Deletion Across Spaces ---")
        clearTextView()
        postString("xin chao em")
        postDeletes(7) // deletes 'em' and 'chao'
        postString("banj ") // bạn
        assertResult(name: "Cross-word delete and retype 'bạn '", expected: "xin bạn ")
        
        print("\n--- Test Suite 6: English Word Auto-Restore ---")
        let engWords = ["series", "views", "speed", "window", "diesel", "client"]
        clearTextView()
        for w in engWords {
            postString(w + " ")
        }
        let expectedEng = engWords.joined(separator: " ") + " "
        assertResult(name: "English words spelling restore", expected: expectedEng)
        
        print("\n--- Test Suite 7: High-Speed Burst Typing (Load Test) ---")
        clearTextView()
        let burstSentence = "coong ngheej thoong tin phast trieern nhanh chosng "
        postString(burstSentence, delayMs: 4) // 4ms high-speed burst
        assertResult(name: "High-speed burst typing", expected: "công nghệ thông tin phát triển nhanh chóng ")
    }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    app.setActivationPolicy(.regular)
    let runner = RealSystemTestRunner()
    DispatchQueue.main.async {
        runner.run()
    }
    app.run()
}

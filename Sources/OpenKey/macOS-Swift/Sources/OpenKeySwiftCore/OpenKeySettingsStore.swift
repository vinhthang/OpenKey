import Foundation
import Observation
#if canImport(AppKit)
import AppKit
#endif

@Observable public final class OpenKeySettingsStore: @unchecked Sendable {
    public static let shared = OpenKeySettingsStore()
    
    // UserDefaults Keys
    public enum Keys {
        public static let language = "Language" // 0: English, 1: Vietnamese
        public static let inputType = "InputType" // 0: Telex, 1: VNI
        public static let checkSpelling = "Spelling"
        public static let restoreIfWrongSpelling = "RestoreIfInvalidWord"
        public static let useModernOrthography = "ModernOrthography"
        public static let fixRecommendBrowser = "FixRecommendBrowser"
        public static let useSmartSwitchKey = "UseSmartSwitchKey"
        public static let otherLanguage = "OtherLanguage"
        public static let switchKeyStatus = "SwitchKeyStatus"
        public static let beepOnSwitch = "BeepOnSwitch"
        public static let smartSwitchData = "SmartSwitchData"
        public static let autoWordingEnabled = "AutoWordingEnabled"
        public static let grammarRepairEnabled = "GrammarRepairEnabled"
        public static let shorthandExpansionEnabled = "ShorthandExpansionEnabled"
        public static let candidateSuggestionsEnabled = "CandidateSuggestionsEnabled"
        public static let customShorthands = "CustomShorthandsData"
    }
    
    // Default switch key: Option + Z (0x7A000206)
    public static let defaultSwitchKey: Int = 0x7A000206
    
    public var activeAppBundleId: String?
    public var onLanguageChanged: (@MainActor @Sendable (Int) -> Void)?
    private var isApplyingSmartSwitch: Bool = false
    
    public var language: Int {
        didSet {
            UserDefaults.standard.set(language, forKey: Keys.language)
            syncToEngine()
            if let callback = onLanguageChanged {
                if Thread.isMainThread {
                    MainActor.assumeIsolated { callback(language) }
                } else {
                    DispatchQueue.main.async { callback(self.language) }
                }
            }
            if !isApplyingSmartSwitch && useSmartSwitchKey {
                var targetBundleId = activeAppBundleId
                if targetBundleId == nil {
                    #if canImport(AppKit)
                    if let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
                       front != "com.tuyenmai.openkey.swift" {
                        targetBundleId = front
                    }
                    #endif
                }
                if let bundleId = targetBundleId {
                    OKSetAppInputMethodStatus(bundleId, Int32(language))
                    saveSmartSwitchData()
                }
            }
        }
    }
    
    public var inputType: Int {
        didSet {
            if inputType != 0 && inputType != 1 {
                inputType = 0
                return
            }
            UserDefaults.standard.set(inputType, forKey: Keys.inputType)
            syncToEngine()
        }
    }
    
    public var checkSpelling: Bool {
        didSet {
            UserDefaults.standard.set(checkSpelling, forKey: Keys.checkSpelling)
            syncToEngine()
        }
    }
    
    public var restoreIfWrongSpelling: Bool {
        didSet {
            UserDefaults.standard.set(restoreIfWrongSpelling, forKey: Keys.restoreIfWrongSpelling)
            syncToEngine()
        }
    }
    
    public var useModernOrthography: Bool {
        didSet {
            UserDefaults.standard.set(useModernOrthography, forKey: Keys.useModernOrthography)
            syncToEngine()
        }
    }
    
    public var fixRecommendBrowser: Bool {
        didSet {
            UserDefaults.standard.set(fixRecommendBrowser, forKey: Keys.fixRecommendBrowser)
            syncToEngine()
        }
    }
    
    public var useSmartSwitchKey: Bool {
        didSet {
            UserDefaults.standard.set(useSmartSwitchKey, forKey: Keys.useSmartSwitchKey)
            syncToEngine()
            if useSmartSwitchKey {
                var targetBundleId = activeAppBundleId
                #if canImport(AppKit)
                if targetBundleId == nil,
                   let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
                   front != "com.tuyenmai.openkey.swift" {
                    targetBundleId = front
                }
                #endif
                if let bundleId = targetBundleId {
                    OKSetAppInputMethodStatus(bundleId, Int32(language))
                    saveSmartSwitchData()
                }
            }
        }
    }
    
    public var otherLanguage: Bool {
        didSet {
            UserDefaults.standard.set(otherLanguage, forKey: Keys.otherLanguage)
        }
    }
    
    public var switchKeyStatus: Int {
        didSet {
            UserDefaults.standard.set(switchKeyStatus, forKey: Keys.switchKeyStatus)
        }
    }
    
    public var beepOnSwitch: Bool {
        didSet {
            UserDefaults.standard.set(beepOnSwitch, forKey: Keys.beepOnSwitch)
        }
    }
    
    public var autoWordingEnabled: Bool {
        didSet {
            UserDefaults.standard.set(autoWordingEnabled, forKey: Keys.autoWordingEnabled)
            syncToEngine()
        }
    }
    
    public var grammarRepairEnabled: Bool {
        didSet {
            UserDefaults.standard.set(grammarRepairEnabled, forKey: Keys.grammarRepairEnabled)
            syncToEngine()
        }
    }
    
    public var shorthandExpansionEnabled: Bool {
        didSet {
            UserDefaults.standard.set(shorthandExpansionEnabled, forKey: Keys.shorthandExpansionEnabled)
            syncToEngine()
        }
    }
    
    public var candidateSuggestionsEnabled: Bool {
        didSet {
            UserDefaults.standard.set(candidateSuggestionsEnabled, forKey: Keys.candidateSuggestionsEnabled)
            syncToEngine()
        }
    }
    
    public var customShorthands: [String: String] {
        didSet {
            UserDefaults.standard.set(customShorthands, forKey: Keys.customShorthands)
            syncToEngine()
        }
    }
    
    public var launchAtLogin: Bool = false
    public var isAccessibilityTrusted: Bool = false
    
    public init() {
        let defaults = UserDefaults.standard
        defaults.register(defaults: [
            Keys.language: 1, // Vietnamese by default
            Keys.inputType: 0, // Telex by default
            Keys.checkSpelling: true,
            Keys.restoreIfWrongSpelling: true,
            Keys.useModernOrthography: true,
            Keys.fixRecommendBrowser: true,
            Keys.useSmartSwitchKey: true,
            Keys.otherLanguage: true,
            Keys.switchKeyStatus: Self.defaultSwitchKey,
            Keys.beepOnSwitch: false,
            Keys.autoWordingEnabled: false,
            Keys.grammarRepairEnabled: false,
            Keys.shorthandExpansionEnabled: false,
            Keys.candidateSuggestionsEnabled: false
        ])
        
        self.language = defaults.integer(forKey: Keys.language)
        let rawInputType = defaults.integer(forKey: Keys.inputType)
        self.inputType = (rawInputType == 1) ? 1 : 0
        self.checkSpelling = defaults.bool(forKey: Keys.checkSpelling)
        self.restoreIfWrongSpelling = defaults.bool(forKey: Keys.restoreIfWrongSpelling)
        self.useModernOrthography = defaults.bool(forKey: Keys.useModernOrthography)
        self.fixRecommendBrowser = defaults.bool(forKey: Keys.fixRecommendBrowser)
        self.useSmartSwitchKey = defaults.bool(forKey: Keys.useSmartSwitchKey)
        self.otherLanguage = defaults.bool(forKey: Keys.otherLanguage)
        self.switchKeyStatus = defaults.integer(forKey: Keys.switchKeyStatus)
        self.beepOnSwitch = defaults.bool(forKey: Keys.beepOnSwitch)
        self.autoWordingEnabled = defaults.bool(forKey: Keys.autoWordingEnabled)
        self.grammarRepairEnabled = defaults.bool(forKey: Keys.grammarRepairEnabled)
        self.shorthandExpansionEnabled = defaults.bool(forKey: Keys.shorthandExpansionEnabled)
        self.candidateSuggestionsEnabled = defaults.bool(forKey: Keys.candidateSuggestionsEnabled)
        self.customShorthands = defaults.dictionary(forKey: Keys.customShorthands) as? [String: String] ?? [:]
        
        OKEngineInit()
        
        if let data = defaults.data(forKey: Keys.smartSwitchData) {
            data.withUnsafeBytes { rawBuffer in
                if let base = rawBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self) {
                    OKInitSmartSwitchKey(base, Int32(rawBuffer.count))
                }
            }
        }
        
        syncToEngine()
    }
    
    public func applySmartSwitchLanguage(_ newLang: Int) {
        isApplyingSmartSwitch = true
        self.language = newLang
        isApplyingSmartSwitch = false
    }
    
    public func saveSmartSwitchData() {
        let size = OKGetSmartSwitchKeySaveData(nil, 0)
        guard size > 0 else { return }
        var buffer = [UInt8](repeating: 0, count: Int(size))
        _ = OKGetSmartSwitchKeySaveData(&buffer, Int32(size))
        UserDefaults.standard.set(Data(buffer), forKey: Keys.smartSwitchData)
    }
    
    public func syncToEngine() {
        OKEngineSyncConfig(
            Int32(language),
            Int32(inputType),
            checkSpelling ? 1 : 0,
            useModernOrthography ? 1 : 0,
            restoreIfWrongSpelling ? 1 : 0,
            fixRecommendBrowser ? 1 : 0,
            useSmartSwitchKey ? 1 : 0,
            autoWordingEnabled ? 1 : 0,
            grammarRepairEnabled ? 1 : 0,
            shorthandExpansionEnabled ? 1 : 0,
            candidateSuggestionsEnabled ? 1 : 0
        )
        AutoWordingEngine.shared.isEnabled = autoWordingEnabled
        AutoWordingEngine.shared.grammarRepairEnabled = grammarRepairEnabled
        AutoWordingEngine.shared.shorthandExpansionEnabled = shorthandExpansionEnabled
        AutoWordingEngine.shared.candidateSuggestionsEnabled = candidateSuggestionsEnabled
        AutoWordingEngine.shared.customShorthands = customShorthands
    }
    
    public func setCustomShorthand(trigger: String, replacement: String) {
        let cleanTrigger = trigger.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let cleanReplacement = replacement.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTrigger.isEmpty && !cleanReplacement.isEmpty else { return }
        customShorthands[cleanTrigger] = cleanReplacement
    }
    
    public func removeCustomShorthand(trigger: String) {
        let cleanTrigger = trigger.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        customShorthands.removeValue(forKey: cleanTrigger)
    }
    
    public func toggleLanguage() {
        language = (language == 1) ? 0 : 1
        if beepOnSwitch {
            #if canImport(AppKit)
            NSSound.beep()
            #endif
        }
    }
}

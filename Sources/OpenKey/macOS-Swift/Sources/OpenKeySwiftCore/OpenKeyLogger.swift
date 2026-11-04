//
//  OpenKeyLogger.swift
//  OpenKeySwiftCore
//
//  Version-scoped persistent asynchronous file logging and diagnostic subsystem (REQ-013, ADR-012).
//

import Foundation
#if canImport(AppKit)
import AppKit
#endif

public enum OpenKeyLogCategory: String, Sendable {
    case lifecycle = "LIFECYCLE"
    case settings = "SETTINGS"
    case eventTap = "EVENT_TAP"
    case engine = "ENGINE"
    case autoWording = "AUTO_WORDING"
    case injector = "INJECTOR"
    case candidateBar = "CANDIDATE_BAR"
    case smartSwitch = "SMART_SWITCH"
}

public final class OpenKeyLogger: @unchecked Sendable {
    public static let shared = OpenKeyLogger()
    
    private let lock = NSLock()
    private let queue = DispatchQueue(label: "com.tuyenmai.openkey.logger", qos: .utility)
    
    private var _isEnabled: Bool = false
    public var isEnabled: Bool {
        get { lock.withLock { _isEnabled } }
        set {
            let changed: Bool = lock.withLock {
                guard _isEnabled != newValue else { return false }
                _isEnabled = newValue
                return true
            }
            if changed && newValue {
                checkVersionRetention()
                log(.lifecycle, "OpenKeyLogger enabled (version: \(resolvedVersionStamp))")
            }
        }
    }
    
    private var customLogDirectoryURL: URL?
    private var customVersionStamp: String?
    private var customMaxFileSizeBytes: Int?
    
    public var logDirectoryURL: URL {
        lock.withLock {
            if let custom = customLogDirectoryURL { return custom }
            let logsDir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first!
                .appendingPathComponent("Logs", isDirectory: true)
                .appendingPathComponent("OpenKeySwift", isDirectory: true)
            return logsDir
        }
    }
    
    public var logFileURL: URL {
        logDirectoryURL.appendingPathComponent("openkey-debug.log")
    }
    
    public var maxFileSizeBytes: Int {
        lock.withLock { customMaxFileSizeBytes ?? (20 * 1024 * 1024) }
    }
    
    public var resolvedVersionStamp: String {
        lock.withLock {
            if let custom = customVersionStamp { return custom }
            let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "2.0.0"
            let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
            return "\(short)-build\(build)"
        }
    }
    
    private let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        df.locale = Locale(identifier: "en_US_POSIX")
        return df
    }()
    
    public func configureForTesting(
        logDirectoryURL: URL,
        appVersionStamp: String,
        maxFileSizeBytes: Int = 20 * 1024 * 1024
    ) {
        lock.withLock {
            self.customLogDirectoryURL = logDirectoryURL
            self.customVersionStamp = appVersionStamp
            self.customMaxFileSizeBytes = maxFileSizeBytes
        }
        checkVersionRetention(currentStamp: appVersionStamp)
    }
    
    public func checkVersionRetention(currentStamp: String? = nil) {
        queue.sync {
            let stamp = currentStamp ?? resolvedVersionStamp
            let dir = logDirectoryURL
            let file = logFileURL
            
            // Remove legacy/rotated .log files in log directory other than openkey-debug.log
            if let contents = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) {
                for item in contents where item.lastPathComponent != "openkey-debug.log" && item.pathExtension == "log" {
                    try? FileManager.default.removeItem(at: item)
                }
            }
            
            if FileManager.default.fileExists(atPath: file.path) {
                var needsPurge = true
                if let handle = try? FileHandle(forReadingFrom: file) {
                    defer { try? handle.close() }
                    let data = handle.readData(ofLength: 512)
                    if let firstLine = String(data: data, encoding: .utf8)?.components(separatedBy: "\n").first,
                       firstLine.starts(with: "# OpenKeySwiftVersionStamp:") {
                        let existingStamp = firstLine.replacingOccurrences(of: "# OpenKeySwiftVersionStamp:", with: "").trimmingCharacters(in: .whitespaces)
                        if existingStamp == stamp {
                            needsPurge = false
                        }
                    }
                }
                if needsPurge {
                    recreateLogFile(stamp: stamp)
                }
            } else if isEnabled {
                try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                recreateLogFile(stamp: stamp)
            }
        }
    }
    
    private func recreateLogFile(stamp: String) {
        let dir = logDirectoryURL
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = logFileURL
        let header = "# OpenKeySwiftVersionStamp: \(stamp)\n# Initialized: \(ISO8601DateFormatter().string(from: Date()))\n"
        try? header.write(to: file, atomically: true, encoding: .utf8)
    }
    
    @inline(__always)
    public func log(_ category: OpenKeyLogCategory, _ message: @autoclosure () -> String) {
        guard isEnabled else { return }
        let msg = message()
        let cat = category.rawValue
        queue.async { [weak self] in
            guard let self = self else { return }
            self.appendLogEntry(category: cat, message: msg)
        }
    }
    
    private func appendLogEntry(category: String, message: String) {
        let file = logFileURL
        if !FileManager.default.fileExists(atPath: file.path) {
            recreateLogFile(stamp: resolvedVersionStamp)
        }
        
        let now = dateFormatter.string(from: Date())
        let line = "[\(now)] [\(category)] \(message)\n"
        guard let lineData = line.data(using: .utf8) else { return }
        
        let currentSize = (try? FileManager.default.attributesOfItem(atPath: file.path)[.size] as? NSNumber)?.intValue ?? 0
        if currentSize + lineData.count > maxFileSizeBytes {
            recreateLogFile(stamp: resolvedVersionStamp)
            let rotationNotice = "[\(now)] [LIFECYCLE] [LOG_ROTATED_SIZE_CAP] Log file truncated at size cap \(maxFileSizeBytes) bytes\n"
            if let rotData = rotationNotice.data(using: .utf8),
               let handle = try? FileHandle(forWritingTo: file) {
                handle.seekToEndOfFile()
                handle.write(rotData)
                try? handle.close()
            }
        }
        
        if let handle = try? FileHandle(forWritingTo: file) {
            handle.seekToEndOfFile()
            handle.write(lineData)
            try? handle.close()
        }
    }
    
    public func clearLog() {
        queue.sync {
            recreateLogFile(stamp: resolvedVersionStamp)
        }
    }
    
    public func flushForTesting() {
        queue.sync {}
    }
    
    public func openLogFile() {
        #if canImport(AppKit)
        let url = logFileURL
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.open(url)
        }
        #endif
    }
    
    public func revealLogInFinder() {
        #if canImport(AppKit)
        let url = logFileURL
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            NSWorkspace.shared.open(logDirectoryURL)
        }
        #endif
    }
}

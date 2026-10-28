//
//  SmartSwitchStore.swift
//  OpenKeySwiftCore
//
//  Converted to 100% Pure Swift 6 by Antigravity from the original C++ OpenKey engine:
//  Created by Mai Vũ Tuyên on 1/18/19.
//  Copyright © 2019 Mai Vũ Tuyên. All rights reserved.
//  Licensed under GNU General Public License v3.0.
//

import Foundation

public final class SmartSwitchStore: @unchecked Sendable {
    public static let shared = SmartSwitchStore()
    
    private let lock = NSLock()
    private var smartSwitchData: [String: Int8] = [:]
    private var smartSwitchCacheKey: String = ""
    private var smartSwitchCacheData: Int8 = 0
    
    public init() {}
    
    public func initSmartSwitchKey(data: UnsafePointer<UInt8>?, size: Int32) {
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
    
    public func getSmartSwitchKeySaveData(outBuffer: UnsafeMutablePointer<UInt8>?, maxBufferSize: Int32) -> Int32 {
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
    
    public func getAppInputMethodStatus(bundleId: String, currentInputMethod: Int32) -> Int32 {
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
    
    public func setAppInputMethodStatus(bundleId: String, language: Int32) {
        lock.lock()
        defer { lock.unlock() }
        smartSwitchData[bundleId] = Int8(language)
        smartSwitchCacheKey = bundleId
        smartSwitchCacheData = Int8(language)
    }
}

// MARK: - Public C-ABI Bridge Functions for SmartSwitchKey

public func OKInitSmartSwitchKey(_ data: UnsafePointer<UInt8>?, _ size: Int32) {
    SmartSwitchStore.shared.initSmartSwitchKey(data: data, size: size)
}

public func OKGetAppInputMethodStatus(_ bundleId: String, _ currentInputMethod: Int32) -> Int32 {
    SmartSwitchStore.shared.getAppInputMethodStatus(bundleId: bundleId, currentInputMethod: currentInputMethod)
}

public func OKSetAppInputMethodStatus(_ bundleId: String, _ language: Int32) {
    SmartSwitchStore.shared.setAppInputMethodStatus(bundleId: bundleId, language: language)
}

public func OKGetSmartSwitchKeySaveData(_ outBuffer: UnsafeMutablePointer<UInt8>?, _ maxBufferSize: Int32) -> Int32 {
    SmartSwitchStore.shared.getSmartSwitchKeySaveData(outBuffer: outBuffer, maxBufferSize: maxBufferSize)
}

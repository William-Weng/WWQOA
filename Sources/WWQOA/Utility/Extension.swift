//
//  Extension.swift
//  WWQOA
//
//  Created by William.Weng on 2026/04/20.
//

import UIKit


// MARK: - Int16 Clamping Helper

extension Int16 {
    
    init(clamping value: Int32) {
        if value > 32767 {
            self = 32767
        } else if value < -32768 {
            self = -32768
        } else {
            self = Int16(value)
        }
    }
}

// MARK: - Int32
extension Int32 {
    
    /// 限制值於 Int16 有效範圍：[-32768, 32767] => QOA 重建過程中防止溢位，保證解碼安全性
    /// - Returns: 安全範圍內的 Int16
    func clamp16() -> Int16 {
        
        if self > WWQOA.LMS.maxInt16 { return Int16(WWQOA.LMS.maxInt16) }
        if self < WWQOA.LMS.minInt16 { return Int16(WWQOA.LMS.minInt16) }
        
        return Int16(self)
    }
}

// MARK: - Int64
extension Int64 {
    
    /// 計算平方值，專為音頻壓縮誤差計算設計 => 保證非負：(-5).square() = 25 / 防溢位：Int64 範圍足夠容納 Int16 平方和
    /// - Returns: Self
    func square() -> Self {
        return self * self
    }
}

// MARK: - Double
extension Double {
    
    /// QOA 規範指定的四捨五入演算法 => 等價於標準 `round()`，但用 floor/ceil 實現精確控制
    /// - Parameters:
    ///   - value: 浮點數（來自 pow() 計算）
    /// - Returns: 最接近的整數（Double 形式）
    func qoaRound() -> Double {
        if (self < 0) { return ceil(self - 0.5) }
        return floor(self + 0.5)
    }
}

// MARK: - String
extension String {
    
    /// 字串轉成[UInt8] ("qoif" => [0x71, 0x6F, 0x69, 0x66])
    /// - Parameter str: String
    /// - Returns: [UInt8]
    func toUInt8() -> [UInt8] { return Array(utf8) }
}

extension Data {
    
    /// 從 UInt8 轉成 Data，方便用在 "qoaf" 這種常數
    init(contentsOf bytes: [UInt8]) {
        self.init(bytes)
    }
    
    /// 用[大端序](https://blog.gtwang.org/programming/difference-between-big-endian-and-little-endian-implementation-in-c/)寫入[FixedWidthInteger](https://developer.apple.com/documentation/swift/fixedwidthinteger)（例如 UInt8, UInt16, UInt32, Int16, Int32 等）
    mutating func appendBigEndian<T: FixedWidthInteger>(_ value: T) {
        var bigEndian = value.bigEndian
        Swift.withUnsafeBytes(of: &bigEndian) { append(contentsOf: $0) }
    }
    
    /// 用小端序寫入
    mutating func appendLittleEndian<T: FixedWidthInteger>(_ value: T) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { buffer in
            append(buffer.bindMemory(to: UInt8.self))
        }
    }
}


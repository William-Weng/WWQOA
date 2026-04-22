//
//  ByteReader.swift
//  WWQOA
//
//  Created by William.Weng on 2026/04/20.
//

import Foundation

// MARK: - 無號數
extension WWQOA.ByteReader {
    
    /// 讀取二進制無號數值 (位移取值 + 累加)
    /// - Returns: FixedWidthInteger & UnsignedInteger
    mutating func readUIntValue<T: FixedWidthInteger & UnsignedInteger>() throws -> T {
        let size = MemoryLayout<T>.size
        return try readUIntValue(size: size)
    }
    
    /// 讀取二進制無號數值 (位移取值 + 累加)
    /// - Returns: UInt32
    mutating func readUInt24Value() throws -> UInt32 {
        return try readUIntValue(size: 3) as UInt32
    }
}

// MARK: - 有號數
extension WWQOA.ByteReader {
    
    /// 讀取二進制有號數值 (位移取值 + 累加)
    /// - Returns: FixedWidthInteger & SignedInteger
    mutating func readIntValue<T: FixedWidthInteger & SignedInteger>() throws -> T {
        
        switch T.self {
        case is Int8.Type:
            let value = try readUIntValue() as UInt8
            return Int8(bitPattern: value) as! T
        case is Int16.Type:
            let value = try readUIntValue() as UInt16
            return Int16(bitPattern: value) as! T
        case is Int32.Type:
            let value = try readUIntValue() as UInt32
            return Int32(bitPattern: value) as! T
        case is Int64.Type:
            let value = try readUIntValue() as UInt64
            return Int64(bitPattern: value) as! T
        case is Int.Type:
            let value = try readUIntValue() as UInt
            return Int(bitPattern: value) as! T
        default:
            fatalError("Unsupported Int type \(T.self)")
        }
    }
}

// MARK: - 小工具
private extension WWQOA.ByteReader {
    
    /// 讀取二進制無號數值 (位移取值 + 累加)
    /// - Returns: FixedWidthInteger
    mutating func readUIntValue<T: FixedWidthInteger>(size: Int) throws -> T {
        
        if ((offset + size) > data.count)  { throw WWQOA.FileDecodeError.insufficientData }
        
        let value = (0..<size).map { index in
            return T(data[offset + index]) << (8 * (size - index - 1))      // let b0 = UInt16(data[offset]) << 8
        }.reduce(T(0)) { partialResult, number in
            return partialResult | number                                   // b0 | b1
        }
        
        offset += size
        
        return value
    }
}

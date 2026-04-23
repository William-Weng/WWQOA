//
//  WWQOA.swift
//  WWQOA
//
//  Created by William.Weng on 2026/04/20.
//

import UIKit

// MARK: - [Quite Ok Audio](https://qoaformat.org/)
public struct WWQOA: Sendable {
    
    public static let shared: WWQOA = .init()
    
    private let encoder: FileEncoder = .init()
    private let decoder: FileDecoder = .init()
    private let wavEncoder = WavEncoder()
    
    public init() {}
}

// MARK: - 公開函式 (編碼)
public extension WWQOA {
    
    /// 取得QOA編碼完成的結果
    /// - Parameter input: 整段 interleaved PCM，以及相關 metadata
    /// - Returns: 完整 .qoa 檔案資料與統計資訊
    func encodeFile(_ input: WWQOA.FileEncodeInput) -> FileEncodeResult {
        return encoder.encodeFile(input)
    }
    
    /// 將編碼完成的QOA檔存成檔案
    /// - Parameters:
    ///   - input: 整段 interleaved PCM，以及相關 metadata
    ///   - url: 目標 QOA 檔案路徑
    /// - Returns: 整個 QOA 檔案的編碼資訊
    func encodeFile(_ input: WWQOA.FileEncodeInput, to url: URL) throws -> FileEncodeInformation {
        
        let result = encodeFile(input)
        try result.data.write(to: url)
        
        return result.information()
    }
}

// MARK: - 公開函式 (解碼)
public extension WWQOA {
    
    /// 解碼完整的 QOA 檔案為 `FileDecodeResult`
    /// - Parameter data: 完整的 QOA 檔案資料
    /// - Returns: 包含所有 PCM samples 和 metadata 的解碼結果
    /// - Throws: 各種解碼錯誤，包括格式錯誤、資料不足、checksum 不符等
    func decodeFile(_ data: Data) throws -> FileDecodeResult {
        return try decoder.decodeFile(data)
    }
    
    /// 解碼 QOA 檔案並直接匯出為 WAV 檔案
    /// - Parameters:
    ///   - data: 輸入的 QOA 檔案資料
    ///   - url: 目標 WAV 檔案路徑
    /// - Throws: 解碼錯誤、檔案寫入錯誤、WAV header 生成錯誤等
    func decodeFile(_ data: Data, to url: URL) throws -> WWQOA.FileDecodeInformation {
        
        let result = try decodeFile(data)
        let wavData = try wavEncoder.makeData(samples: result.interleavedSamples, channels: result.channels, sampleRate: result.sampleRate)
        
        try wavData.write(to: url)
        
        return result.information(count: wavData.count)
    }
}



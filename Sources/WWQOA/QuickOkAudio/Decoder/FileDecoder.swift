//
//  FileDecoder.swift
//  WWQOA
//
//  Created by iOS on 2026/4/20.
//

import Foundation
import WWByteReader

// MARK: - 公開函式
extension WWQOA.FileDecoder {
        
    /// 解碼完整 QOA 檔案
    func decodeFile(_ data: Data) throws -> WWQOA.FileDecodeResult {
        
        var reader = WWByteReader(data: data)

        let magic = try readMagic(from: &reader)
        
        if (magic != WWQOA.Constant.magic) { throw WWQOA.FileDecodeError.invalidMagic }
        
        let samplesPerChannelInHeader = try reader.readUIntValue() as UInt32
        let isStreaming = (samplesPerChannelInHeader == WWQOA.Constant.streamingSamples)
        
        var frameHeaders: [WWQOA.FrameHeader] = []
        var allPlanarSamples: [[Int16]] = []
        var staticChannels: Int?
        var staticSampleRate: Int?
        
        while (reader.offset < data.count) {
            
            let remaining = data.subdata(in: reader.offset..<data.count)
            let frame = try frameDecoder.decodeFrame(remaining)
            
            frameHeaders.append(frame.header)
            
            try checkFrameConsistency(with: frame, staticChannels: &staticChannels, staticSampleRate: &staticSampleRate, isStreaming: isStreaming)
            
            if allPlanarSamples.isEmpty { allPlanarSamples = Array(repeating: [], count: frame.header.channels) }
            if (allPlanarSamples.count != frame.header.channels) { throw WWQOA.FileDecodeError.inconsistentStaticFileChannels }
            
            for channel in 0..<frame.header.channels {
                allPlanarSamples[channel].append(contentsOf: frame.planarSamples[channel])
            }

            reader.offset += frame.bytesRead
        }

        if (frameHeaders.isEmpty) { throw WWQOA.FileDecodeError.noFrames }
                
        let channels = staticChannels ?? frameHeaders[0].channels
        let sampleRate = staticSampleRate ?? frameHeaders[0].sampleRate
        let interleavedSamples = interleave(allPlanarSamples)
        
        if (!isStreaming) {
            let actualSamplesPerChannel = (allPlanarSamples.first?.count ?? 0)
            if (actualSamplesPerChannel != Int(samplesPerChannelInHeader)) { throw WWQOA.FileDecodeError.sampleCountMismatch }
        }
        
        return .init(samplesPerChannelInHeader: samplesPerChannelInHeader, frameHeaders: frameHeaders, interleavedSamples: interleavedSamples, planarSamples: allPlanarSamples, channels: channels, sampleRate: sampleRate
        )
    }
}

// MARK: - 小工具
private extension WWQOA.FileDecoder {
    
    /// 讀取檔頭 => magic number: "qoaf"
    /// - Parameter reader: WWQOA.ByteReader
    /// - Returns: [UInt8]
    func readMagic(from reader: inout WWByteReader) throws -> [UInt8] {
        
        let count = WWQOA.Constant.magic.count
        
        var bytes: [UInt8] = []
        bytes.reserveCapacity(count)
        
        for _ in 0..<count {
            let value = try reader.readUIntValue() as UInt8
            bytes.append(value)
        }
        
        return bytes
    }
    
    /// 驗證 frame header 與檔案規格是否一致 => 建立檔案規格（第一次）或驗證一致性（之後）。
    /// - Parameters:
    ///   - frame: 當前 frame 的解碼結果
    ///   - staticChannels: 檔案聲道數（nil 表示首次設定）
    ///   - staticSampleRate: 檔案採樣率（nil 表示首次設定）
    ///   - isStreaming: 是否為串流模式（串流模式放寬檢查）
    /// - Throws: 規格不一致錯誤
    /// - Returns: 更新後的 `staticChannels` 和 `staticSampleRate`
    func checkFrameConsistency(with frame: WWQOA.FrameDecodeResult, staticChannels: inout Int?, staticSampleRate: inout Int?, isStreaming: Bool) throws {
        
        staticChannels = staticChannels ?? frame.header.channels
        if (!isStreaming && staticChannels != frame.header.channels) { throw WWQOA.FileDecodeError.inconsistentStaticFileChannels }
        
        staticSampleRate = staticSampleRate ?? frame.header.sampleRate
        if (!isStreaming && staticSampleRate != frame.header.sampleRate) { throw WWQOA.FileDecodeError.inconsistentStaticFileSampleRate }
    }
    
    /// 將 **planar** PCM samples 轉換為 **interleaved** 格式
    ///
    /// ### PCM 兩種常見儲存格式：
    /// | 格式 | 結構 | 用途 |
    /// |------|------|------|
    /// | **Planar** | `[[L0,L1,L2,...], [R0,R1,R2,...]]` | DSP（FFT、filtering）、多聲道處理 |
    /// | **Interleaved** | `[L0,R0, L1,R1, L2,R2, ...]` | WAV、MP3、AAC 檔案格式 |
    ///
    /// ### 轉換邏輯：
    /// `interleaved[i * channels + c] = planar[c][i]`
    ///
    /// 時間索引 `i` 在外層，聲道索引 `c` 在內層。
    ///
    /// ### 假設：
    /// - 所有聲道長度相同（以第一聲道長度為準）
    /// - 若輸入為空，直接回傳空陣列
    ///
    /// - Parameter planar: 輸入的 **planar** PCM samples，`planar[c]` 是第 c 聲道的樣本
    /// - Returns: **Interleaved** PCM samples，`[ch0_s0, ch1_s0, ..., ch0_s1, ch1_s1, ...]`
    /// - Complexity: O(n)，n = 總樣本數
    func interleave(_ planar: [[Int16]]) -> [Int16] {
        
        guard let first = planar.first else { return [] }
        
        let channels = planar.count
        let samplesPerChannel = first.count
        
        var interleaved: [Int16] = []
        interleaved.reserveCapacity(channels * samplesPerChannel)
        
        for index in 0..<samplesPerChannel {
            for channel in 0..<channels {
                interleaved.append(planar[channel][index])
            }
        }
        
        return interleaved
    }
}

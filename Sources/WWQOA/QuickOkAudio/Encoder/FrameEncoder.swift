//
//  FrameEncoder.swift
//  WWQOA
//
//  Created by William.Weng on 2026/04/20.
//

import Foundation

// MARK: - 交錯 PCM → 完整的 QOA Frame Data (header + LMS states + slices) (格式切片)
extension WWQOA.FrameEncoder {
    
    /// 組合完整的 QOA frame（header + LMS states + slices）
    /// - 按 QOA 檔案格式規範正確排序：header(8B) → LMS states → channel-interleaved slices
    /// - Parameters:
    ///   - input: FrameInput（包含交錯 PCM、取樣率、聲道數）
    ///   - initialLMSStates: 初始 LMS 狀態，nil 則每個 frame 獨立（規格允許）
    /// - Returns: 完整的 FrameEncodeResult（Data + metadata）
    func encodeFrame(_ input: WWQOA.FrameInput, initialLMSStates: [WWQOA.LMSState]? = nil) -> WWQOA.FrameEncodeResult {
        
        precondition(input.samplesPerChannel > 0, "A QOA frame must contain at least one sample per channel.")
        precondition(input.samplesPerChannel <= WWQOA.Constant.maxSamplesPerFrame, "A frame can contain at most 5120 samples per channel.")
        
        let startLMSStates = startLMSStatesMaker(initialLMSStates: initialLMSStates, channels: input.channels)
        let slicesPerChannel = calculateSlicesPerChannel(input.samplesPerChannel)
        let frameSize = calculateFrameSize(channels: input.channels, slicesPerChannel: slicesPerChannel)
        let encodedSlicesByChannel = encodedSlices(input: input, initialLMSStates: initialLMSStates)
        
        var currentLMSStates = startLMSStates
        var data = Data(capacity: frameSize)

        appendFrameHeader(to: &data, input: input, frameSize: frameSize)

        for channel in 0..<input.channels {
            appendLMSState(startLMSStates[channel], to: &data)
        }
        
        for sliceIndex in 0..<slicesPerChannel {
            for channel in 0..<input.channels {
                let packed = encodedSlicesByChannel[channel][sliceIndex].packedValue
                data.appendBigEndian(packed)
            }
        }
        
        let header = WWQOA.FrameHeader(channels: input.channels, sampleRate: input.sampleRate, samplesPerChannel: input.samplesPerChannel, frameSize: frameSize)
        
        return .init(data: data, header: header, slicesPerChannel: slicesPerChannel, startLMSStates: startLMSStates, endLMSStates: currentLMSStates)
    }
}

// MARK: - 小工具
private extension WWQOA.FrameEncoder {
    
    /// 起始 LMS 狀態決定
    func startLMSStatesMaker(initialLMSStates: [WWQOA.LMSState]?, channels: Int) -> [WWQOA.LMSState] {
        
        if let initialLMSStates {
            precondition(initialLMSStates.count == channels, "Initial LMS states must match channel count.")
            return initialLMSStates
        }
        
        return WWQOA.LMSState.zeroArray(count: channels)
    }
    
    /// 計算每聲道切成幾段 slice（每 slice 有 WWQOA.Constant.sliceSamples 個樣本）
    func calculateSlicesPerChannel(_ samplesPerChannel: Int) -> Int {
        return Int(ceil(Double(samplesPerChannel) / Double(WWQOA.Constant.sliceSamples)))
    }
    
    /// 計算 QOA slice 的樣本範圍
    /// - Parameters:
    ///   - index: Int
    ///   - count: 樣本數量
    /// - Returns: Range<Int>
    func sliceRange(with index: Int, count: Int) -> Range<Int> {
        
        let start = index * WWQOA.Constant.sliceSamples
        let end = min(start + WWQOA.Constant.sliceSamples, count)
        
        return start..<end
    }
    
    /// 計算整個 frame 的 byte 數 => header: 固定大小 + 每聲道都有一份 LMS 狀態（規格要求 record 開頭時的 LMS）+ 每個 slice 佔一個定長的 packedValue（sliceSize）。
    /// - Parameters:
    ///   - channels: 聲道數量
    ///   - slicesPerChannel: 每個聲音的切片大小
    /// - Returns: frameSize = 8 + 2×16 + 256×2×8 = 8 + 32 + 4096 = **4136 bytes**
    func calculateFrameSize(channels: Int, slicesPerChannel: Int) -> Int {
        
        let frameSize = WWQOA.Constant.frameHeaderSize + channels * WWQOA.Constant.lmsStateSizePerChannel + slicesPerChannel * channels * WWQOA.Constant.sliceSize
        return frameSize
    }
    
    /// 將 QOA frame header 寫入 Data (要照順序 => 聲道數 + 取樣取 + 聲道樣本數 + 大小) => [0x02, 0x00, 0xAC, 0x44, 0x14, 0x0F, 0x28, 0x10]
    /// - Parameters:
    ///   - data: 要寫入的Data
    ///   - input: Frame輸入設定值
    ///   - frameSize: Frame大小
    func appendFrameHeader(to data: inout Data, input: WWQOA.FrameInput, frameSize: Int) {
        
        let channels = input.channels
        let sampleRate = input.sampleRate
        let samplesPerChannel = input.samplesPerChannel
        
        precondition(channels > 0 && channels <= 255)
        precondition(sampleRate > 0 && sampleRate <= 0x00FF_FFFF)
        precondition(samplesPerChannel > 0 && samplesPerChannel <= 65535)
        precondition(frameSize > 0 && frameSize <= 65535)
        
        data.append(UInt8(channels))                    // num_channels: uint8_t

        data.append(UInt8((sampleRate >> 16) & 0xFF))   // sampleRate: uint24_t（big‑endian）
        data.append(UInt8((sampleRate >> 8) & 0xFF))
        data.append(UInt8(sampleRate & 0xFF))
        
        data.appendBigEndian(UInt16(samplesPerChannel)) // fsamples: uint16_t（每個聲道樣本數）
        data.appendBigEndian(UInt16(frameSize))         // fsize: uint16_t（這個 frame 的總 byte 數）
    }
    
    /// 將交錯 PCM 解交錯並編碼為 QOA slices
    /// - 純函數：只負責音訊壓縮計算，不產生檔案輸出
    /// - 每個聲道獨立編碼，產生對應的 EncodedSlice 陣列
    /// - Parameters:
    ///   - input: 輸入的 FrameInput（交錯 PCM + 參數）
    ///   - initialLMSStates: 初始 LMS 狀態（預測器），nil 則重置為零狀態
    /// - Returns: 每個聲道的已編碼 slice 陣列 `[[EncodedSlice]]`
    func encodedSlices(input: WWQOA.FrameInput, initialLMSStates: [WWQOA.LMSState]?) -> [[WWQOA.EncodedSlice]] {
        
        let channels = input.channels
        let sampleRate = input.sampleRate
        let samplesPerChannel = input.samplesPerChannel
        
        let startLMSStates = startLMSStatesMaker(initialLMSStates: initialLMSStates, channels: channels)
        let planar = deinterleave(input.interleavedSamples, channels: channels)
        let slicesPerChannel = calculateSlicesPerChannel(samplesPerChannel)
        let frameSize = calculateFrameSize(channels: channels, slicesPerChannel: slicesPerChannel)

        var currentLMSStates = startLMSStates
        var encodedSlices: [[WWQOA.EncodedSlice]] = Array(repeating: [], count: channels)
        
        for channel in 0..<channels {
            
            encodedSlices[channel].reserveCapacity(slicesPerChannel)
            
            let channelSamples = planar[channel]

            for sliceIndex in 0..<slicesPerChannel {
                
                let range = sliceRange(with: sliceIndex, count: channelSamples.count)
                let sliceSamples = Array(channelSamples[range])
                let encoded = sliceEncoder.encode(sliceSamples, lms: currentLMSStates[channel])
                
                encodedSlices[channel].append(encoded)
                currentLMSStates[channel] = encoded.endLMS
            }
        }
        
        return encodedSlices
    }
    
    /// 將 LMS 狀態（history + weights）以 Big‑Endian 寫入 Data。
    /// - Parameters:
    ///   - lms: LMSState
    ///   - data: Data
    func appendLMSState(_ lms: WWQOA.LMSState, to data: inout Data) {
        
        precondition(lms.history.count == 4)
        precondition(lms.weights.count == 4)
        
        for value in lms.history { data.appendBigEndian(Int16(clamping: value)) }   // history[4]: [int16_t]
        for value in lms.weights { data.appendBigEndian(Int16(clamping: value)) }   // weights[4]: [int16_t]
    }
    
    /// 交錯的PCM -> 平面的PCM => 雙聲道 [L0, R0, L1, R1] → planar[0] = [L0, L1], planar[1] = [R0, R1]
    /// - Parameters:
    ///   - samples: [Int16]
    ///   - channels: 聲道數
    /// - Returns: [[Int16]]
    func deinterleave(_ samples: [Int16], channels: Int) -> [[Int16]] {
        
        let samplesPerChannel = samples.count / channels
        
        var planar = Array(repeating: Array<Int16>(), count: channels)
        
        for channel in 0..<channels {
            planar[channel].reserveCapacity(samplesPerChannel)
        }
        
        for frame in 0..<samplesPerChannel {
            let base = frame * channels
            for channel in 0..<channels { planar[channel].append(samples[base + channel]) }
        }

        return planar
    }
}


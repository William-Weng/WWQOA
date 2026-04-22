//
//  FileEncoder.swift
//  WWQOA
//
//  Created by William.Weng on 2026/04/20.
//

import Foundation

// MARK: - 主要功能是「切 frame、組成一個符合 QOA 規格的檔案」 (格式封裝)
extension WWQOA.FileEncoder {
    
    /// 編碼完整 QOA 檔案，將整段 interleaved PCM 包裝成一個 .qoa 檔案，包含：File Header（magic + 總樣本數）/ 連續多個 QOA Frame（每個 frame 有自己的 header + LMS + slice）
    /// - Parameter input: 整段 interleaved PCM，以及相關 metadata
    /// - Returns: 完整 .qoa 檔案資料與統計資訊
    func encodeFile(_ input: WWQOA.FileEncodeInput) -> WWQOA.FileEncodeResult {
        
        precondition(input.actualSamplesPerChannel > 0, "A valid QOA file must contain at least one frame and one sample per channel.")
        
        let channels = input.channels
        let sampleRate = input.sampleRate
        let actualSamplesPerChannel = input.actualSamplesPerChannel
        let totalFrames = input.totalFrames
        let maxFrameSamplesPerChannel = WWQOA.Constant.maxSamplesPerFrame

        var data = Data()
        var currentLMSStates = WWQOA.LMSState.zeroArray(count: channels)
        
        appendFileHeader(to: &data, samplesPerChannel: input.totalSamplesPerChannel)
        
        for frameIndex in 0..<totalFrames {
            
            let frameInput = frameInputMaker(from: input, frameIndex: frameIndex)
            let frameResult = frameEncoder.encodeFrame(frameInput, initialLMSStates: currentLMSStates)
            
            data.append(frameResult.data)
            currentLMSStates = frameResult.endLMSStates
        }
        
        return .init(data: data, frameCount: totalFrames, channels: channels, sampleRate: sampleRate, samplesPerChannelInHeader: input.totalSamplesPerChannel, actualSamplesPerChannel: actualSamplesPerChannel, finalLMSStates: currentLMSStates
        )
    }
}

// MARK: - Internal Helpers
private extension WWQOA.FileEncoder {

    /// 寫入 QOA 檔案的 header => 格式：["q","o","a","f"] + uint32_t（每聲道總樣本數）
    /// - Parameters:
    ///   - data: 要寫入的資料
    ///   - samplesPerChannel: 每聲道總樣本數
    func appendFileHeader(to output: inout Data, samplesPerChannel: UInt32) {
        output.append(contentsOf: WWQOA.Constant.magic)
        output.appendBigEndian(samplesPerChannel)
    }
    
    /// 根據一個 `FileEncodeInput` 與 `frameIndex`，建構出對應該 frame 的 `WWQOA.FrameInput`。
    /// - Parameters:
    ///   - input: 描述整個 QOA 檔案的輸入結構（包含 interleaved PCM、channels、sampleRate 等）
    ///   - frameIndex: 目前要處理的是第幾個 frame（0 開始）
    /// - Returns: 一個準備好送給 `WWQOA.FrameEncoder.encodeFrame(_:)` 使用的 `WWQOA.FrameInput`
    func frameInputMaker(from input: WWQOA.FileEncodeInput, frameIndex: Int) -> WWQOA.FrameInput {
        
        let channels = input.channels
        let maxFrameSamplesPerChannel = WWQOA.Constant.maxSamplesPerFrame
        let startSamplePerChannel = sampleOffset(frameIndex: frameIndex)
        let frameSamplesPerChannel = realSampleFrame(startSamplePerChannel: startSamplePerChannel, actualSamplesPerChannel: input.actualSamplesPerChannel)
        let frameInterleaved = sliceInterleavedFrame(samples: input.interleavedSamples, channels: channels, startSamplePerChannel: startSamplePerChannel, sampleCountPerChannel: frameSamplesPerChannel)
        
        let frameInput = WWQOA.FrameInput(interleavedSamples: frameInterleaved, channels: channels, sampleRate: input.sampleRate)
        return frameInput
    }
    
    /// 從一個 interleaved PCM 陣列中，取出「某一個 frame」的 interleaved 樣本。用來給 `WWQOA.FrameEncoder.encodeFrame(_:)` 用的 `FrameInput.interleavedSamples`。
    /// - Parameters:
    ///   - samples: 整段 interleaved PCM（例如：[L0, R0, L1, R1, ...]）
    ///   - channels: 聲道數（1=mono, 2=stereo...）
    ///   - startSamplePerChannel: 這個 frame 在「每聲道」的起始樣本 index
    ///   - sampleCountPerChannel: 這個 frame 在「每聲道」要切幾個樣本
    /// - Returns: 回傳這個 frame 的 interleaved 樣本陣列 => 雙聲道：[L0, R0, L1, R1, ...]，共 sampleCountPerChannel * channels 個樣本
    func sliceInterleavedFrame(samples: [Int16], channels: Int, startSamplePerChannel: Int, sampleCountPerChannel: Int) -> [Int16] {
        
        precondition(channels > 0)
        precondition(sampleCountPerChannel >= 0)

        var frameSamples: [Int16] = []
        frameSamples.reserveCapacity(sampleCountPerChannel * channels)  // 事先預先分配空間，避免動態增長
        
        for index in 0..<sampleCountPerChannel {

            let globalSampleIndex = startSamplePerChannel + index
            let base = globalSampleIndex * channels

            for channel in 0..<channels {
                frameSamples.append(samples[base + channel])
            }
        }
        
        return frameSamples
    }
        
    /// 這個 frame 實際要處理的「每聲道樣本數」
    /// - Parameters:
    ///   - startSamplePerChannel: Int
    ///   - actualSamplesPerChannel: Int
    /// - Returns: Int
    func realSampleFrame(startSamplePerChannel: Int, actualSamplesPerChannel: Int) -> Int {
        let remaining = actualSamplesPerChannel - startSamplePerChannel
        return max(0, min(WWQOA.Constant.maxSamplesPerFrame, remaining))
    }
    
    /// 這個 frame「在每聲道」的起始樣本 index (offset)
    /// - Parameter frameIndex: Int
    /// - Returns: Int
    func sampleOffset(frameIndex: Int) -> Int {
        return frameIndex * WWQOA.Constant.maxSamplesPerFrame
    }
}

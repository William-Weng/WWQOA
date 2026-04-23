//
//  AudioImporter.swift
//  WWQOA
//
//  Created by William.Weng on 2026/4/20.
//

import AVFoundation

// MARK: - 主工具
extension WWQOA.AudioImporter {

    /// 核心功能：讀取 Apple 可解碼的音訊檔案，統一轉換為 Int16 交錯式 PCM (*.mp3, *.m4a, *.aac, *.wav, *.aiff, *.caf)
    ///
    /// **工作流程：**
    /// 1. 開啟 AVAudioFile，指定輸出格式為 pcmFormatInt16 (非交錯)
    /// 2. 取得音訊基本資訊 (通道數、取樣率、總影格數)
    /// 3. 建立對應格式的 PCM Buffer
    /// 4. 讀取完整檔案到 Buffer
    /// 5. 將非交錯資料重新排列為交錯格式 [L0,R0,L1,R1,...]
    /// 6. 封裝為 WWQOA.FileEncodeInput 回傳
    ///
    /// - Parameter url: 任何 Apple Lossless/MP3/AAC/WAV 等可解碼格式的檔案
    /// - Returns: 交錯式 Int16 PCM 資料 + 音訊參數
    func loadPCMInt16(from url: URL) throws -> WWQOA.FileEncodeInput {
        
        let audioFile = try AVAudioFile(forReading: url, commonFormat: .pcmFormatInt16, interleaved: false)
        
        let processingFormat = audioFile.processingFormat
        let channelCount = Int(processingFormat.channelCount)
        let sampleRate = Int(processingFormat.sampleRate)
        let frameCount = AVAudioFrameCount(audioFile.length)
        
        if (frameCount < 1) { throw WWQOA.AudioImporterError.invalidFrameLength }
        
        guard let buffer = AVAudioPCMBuffer(pcmFormat: processingFormat, frameCapacity: frameCount ) else { throw WWQOA.AudioImporterError.failedToCreateBuffer }
        
        try audioFile.read(into: buffer)
        let samples = try extractInterleavedInt16Samples(from: buffer)
        
        return .init(interleavedSamples: samples, channels: channelCount, sampleRate: sampleRate)
    }
}

// MARK: - 小工具
private extension WWQOA.AudioImporter {

     /// **非交錯 → 交錯 重新排列的核心演算法**
     ///
     /// **輸入格式 (非交錯):**
     /// ```
     /// channelData = [L0, L1, L2, L3, ...]  // 左聲道
     /// channelData = [R0, R1, R2, R3, ...]  // 右聲道[1]
     /// ```
     ///
     /// **輸出格式 (交錯):**
     /// ```
     /// [L0, R0, L1, R1, L2, R2, ...]
     /// ```
     ///
     /// - Parameter buffer: AVAudioPCMBuffer (Int16 非交錯格式)
     /// - Returns: 交錯排列的 Int16 陣列
    func extractInterleavedInt16Samples( from buffer: AVAudioPCMBuffer) throws -> [Int16] {
        
        let channelCount = Int(buffer.format.channelCount)
        let frameLength = Int(buffer.frameLength)
        
        if (frameLength < 0) { throw WWQOA.AudioImporterError.invalidFrameLength }
        
        guard let channelData = buffer.int16ChannelData else { throw WWQOA.AudioImporterError.failedToReadPCMData }
        
        if (channelCount == 1) {
            let mono = UnsafeBufferPointer(start: channelData[0], count: frameLength)
            return Array(mono)
        }
        
        var interleaved: [Int16] = []
        interleaved.reserveCapacity(frameLength * channelCount)
        
        for frame in 0..<frameLength {
            for channel in 0..<channelCount {
                interleaved.append(channelData[channel][frame])
            }
        }
        
        return interleaved
    }
}

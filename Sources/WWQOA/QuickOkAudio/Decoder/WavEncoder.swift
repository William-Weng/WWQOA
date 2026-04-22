//
//  WavEncoder.swift
//  WWQOA
//
//  Created by William.Weng on 2026/04/20.
//

import Foundation

// MARK: PCM => WAV
extension WWQOA.WavEncoder {
    
    /// 將 interleaved Int16 PCM samples 轉成標準 16-bit PCM WAV Data
    /// - Parameters:
    ///   - samples: Interleaved PCM samples，例如 stereo 為 `[L0, R0, L1, R1, ...]`
    ///   - channels: 聲道數
    ///   - sampleRate: 採樣率（Hz）
    /// - Returns: 標準 RIFF/WAVE 16-bit PCM 檔案資料
    func makeData(samples: [Int16], channels: Int, sampleRate: Int) -> Data {
        
        let bitsPerSample: UInt16 = 16
        let audioFormat: UInt16 = 1 // PCM
        let numChannels = UInt16(channels)
        let sampleRate = UInt32(sampleRate)
        let bytesPerSample = MemoryLayout<Int16>.size
        
        let blockAlign = UInt16(channels * bytesPerSample)
        let byteRate = UInt32(Int(sampleRate) * Int(blockAlign))
        let dataChunkSize = UInt32(samples.count * bytesPerSample)
        let riffChunkSize = UInt32(36) + dataChunkSize
        
        var wav = Data()
        wav.reserveCapacity(Int(44 + dataChunkSize))
        
        // RIFF header
        wav.append(contentsOf: Array("RIFF".utf8))
        wav.appendLittleEndian(riffChunkSize)
        wav.append(contentsOf: Array("WAVE".utf8))
        
        // fmt chunk
        wav.append(contentsOf: Array("fmt ".utf8))
        wav.appendLittleEndian(UInt32(16))   // PCM fmt chunk size
        wav.appendLittleEndian(audioFormat)  // 1 = PCM
        wav.appendLittleEndian(numChannels)
        wav.appendLittleEndian(sampleRate)
        wav.appendLittleEndian(byteRate)
        wav.appendLittleEndian(blockAlign)
        wav.appendLittleEndian(bitsPerSample)
        
        // data chunk
        wav.append(contentsOf: Array("data".utf8))
        wav.appendLittleEndian(dataChunkSize)
        
        // PCM samples: 16-bit signed little-endian
        for sample in samples {
            wav.appendLittleEndian(UInt16(bitPattern: sample))
        }
        
        return wav
    }
}

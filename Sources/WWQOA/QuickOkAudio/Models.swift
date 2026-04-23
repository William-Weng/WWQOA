//
//  Models.swift
//  WWQOA
//
//  Created by William.Weng on 2026/04/20.
//

import Foundation

// MARK: - 一般模型
extension WWQOA {
    
    /// QOA 檔案編碼器
    struct FileEncoder {
        let frameEncoder = FrameEncoder()   // Frame編碼器
    }
    
    /// QOA 檔案解碼器
    struct FileDecoder {
        let frameDecoder = FrameDecoder()   // Frame解碼器
    }
    
    /// QOA Frame編碼器
    struct FrameEncoder {
        let sliceEncoder = SliceEncoder()   // 切片編碼器
    }
    
    /// QOA Frame編碼器
    struct FrameDecoder {}

    /// QOA 切片編碼器
    struct SliceEncoder {}
    
    /// 音訊匯入器
    struct AudioImporter {}
    
    /// QOA Frame 編碼器的輸入參數，封裝交錯格式的 PCM 樣本、聲道配置和取樣率，用於單一 frame 編碼。自動計算每個聲道的樣本數、切片數，並提供有效性驗證。
    struct FrameInput: Equatable {
        
        let interleavedSamples: [Int16]/// 交錯格式 PCM 樣本 `[L0,R0,L1,R1,...]`，直接來自 AVAudioPCMBuffer.floatChannelData
        let channels: Int/// 聲道數（1 = 單聲道，2 = 立體聲，QOA 支援 1-255 聲道）
        let sampleRate: Int/// 取樣率（Hz），QOA 固定支援 44100Hz/48000Hz，編碼時會自動驗證

        var samplesPerChannel: Int { calculateSamplesPerChannel() }
        var slicesPerChannel: Int { calculateSlicesPerChannel () }
        var isValidFrameLength: Bool { checkIsValidFrameLength() }
    }
    
    /// 單一 frame 的編碼結果，包含編碼後的壓縮資料、frame 標頭、每個聲道的切片數，以及 LMS 濾波器前後狀態，用於連續 frame 編碼時傳遞狀態，並驗證資料完整性。
    struct FrameEncodeResult: Equatable {
        let data: Data                      // 編碼後的壓縮資料（包含 header + 實際 payload）
        let header: FrameHeader             // Frame 標頭，包含聲道數、樣本數、量化位元等關鍵參數
        let slicesPerChannel: Int           // 每個聲道使用的切片數（slices），決定解碼時的處理粒度
        let startLMSStates: [LMSState]      // 編碼前 LMS 濾波器狀態，用於狀態連續性驗證
        let endLMSStates: [LMSState]        // 編碼後 LMS 濾波器狀態，用於下一個 frame 的初始狀態
    }

    /// 單一 frame 的解碼結果，包含解碼出的音頻樣本（交錯+平面格式）、LMS 狀態變化，以及解析的位元組數。支援 interleaved（CD 標準格式）和 planar（多聲道分離）兩種存取方式。
    struct FrameDecodeResult: Equatable {
        let header: FrameHeader             // 解碼出的 Frame 標頭
        let interleavedSamples: [Int16]     // 交錯格式樣本 `[L0,R0,L1,R1,...]`，直接相容 AVAudioPCMBuffer
        let planarSamples: [[Int16]]        // 平面格式樣本 `[[L0,L1,L2...], [R0,R1,R2...]]`，適合多聲道處理
        let startLMSStates: [LMSState]      // 解碼前 LMS 濾波器狀態
        let endLMSStates: [LMSState]        // 解碼後 LMS 濾波器狀態（供下一個 frame 使用）
        let bytesRead: Int                  // 本 frame 實際解析的位元組數（包含 header + payload）
    }
    
    /// QOA 殘差碼本單元：bestResidualCode() 的試算結果
    struct ResidualChoice {
        let code: UInt8                     // 殘差碼本索引 (0-7)，QOA 規範固定 9 種碼 => 0 = 0, 1 = ±1×sf, 2 = ±3×sf, ... 指數增長
        let sample: Int16                   // 重建樣本值：predicted + residual，經 clamp16() 限制 Int16 範圍
        let residual: Int32                 // 解量化後的實際殘差：dequantizeResidual(code, scalefactor)
        let error: Int64                    // 平方重建誤差：(原始 - sample)^2，貪婪選擇依據 => 最小者勝出，決定此 slice 最終 code
    }
    
    /// QOA slice 完整編碼結果：單一 sfQuant 下的壓縮輸出，16 種量化精度試算後的候選者，供誤差最小者選用
    struct EncodedSlice: Equatable {
        let sfQuant: UInt8                  // 量化精度索引 (0-15)，決定此 slice 的 scalefactor => sfQuant=0：最粗量化，sf=1 => sfQuant=15：最精量化，sf=4096
        let codes: [UInt8]                  // 20 個殘差碼：每個樣本對應的 3-bit 碼本索引 (0-8) => 由 bestResidualCode() 逐樣本選出 => 總計 20×3 = 60 bits + sfQuant 4 bits = 64 bits
        let packedValue: UInt64             // 算術編碼後的壓縮封包：64 bits 固定長度 => 由 packSlice(sfQuant, codes) 產生
        let reconstructed: [Int16]          // 重建樣本序列：原始 PCM 經此 slice 解碼後的結果 => 用於品質驗證：(原始-reconstructed)^2 = error
        let error: Int64                    // 總平方重建誤差：Σ(原始[i] - reconstructed[i])^2 => 16 選 1 的**唯一決策依據**：誤差最小者勝出
        let endLMS: LMSState                // slice 結束時的 LMS 預測器狀態 => 傳遞給下一個 slice，實現跨 slice 連續預測
    }
    
    /// QOA slice 解碼結果：PCM 樣本 + LMS 連續狀態，跨 slice 傳遞的「橋樑」結構，保證無縫連接
    struct DecodedSlice: Equatable {
        let samples: [Int16]                // 解碼後 PCM 樣本序列 => 長度：0-20（末尾 slice 可能短）, 範圍：[-32768, 32767] Int16
        let endLMS: LMSState                // slice 結束時的 LMS 狀態 => 傳遞給下一個 slice，實現時間連續預測
    }
    
    /// Data讀取工具
    struct ByteReader {
        let data: Data                      // 要讀取的資料
        var offset: Int = 0                 // 目前的偏移量
    }
}

// MARK: - 小工具
private extension WWQOA.FrameInput {
    
    /// 每個聲道的實際樣本數
    /// - Returns: Int
    func calculateSamplesPerChannel() -> Int {
        return interleavedSamples.count / channels
    }
    
    /// 每個聲道所需的切片數（slices）
    /// - Returns: Int
    func calculateSlicesPerChannel() -> Int {
        return Int(ceil(Double(samplesPerChannel) / Double(WWQOA.Constant.sliceSamples)))
    }
    
    /// 驗證 frame 長度是否為有效 QOA frame
    /// - Returns: Bool
    func checkIsValidFrameLength() -> Bool {
        return samplesPerChannel > 0 && samplesPerChannel <= WWQOA.Constant.maxSamplesPerFrame
    }
}

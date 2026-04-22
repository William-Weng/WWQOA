//
//  Constant.swift
//  WWQOA
//
//  Created by William.Weng on 2026/04/20.
//

import UIKit

// MARK: - QOA 檔案格式相關常數
extension WWQOA {
    
    enum Constant {
        
        static let magic: [UInt8] = Array("qoaf".utf8)                  // 檔頭 magic number: "qoaf" = [0x71, 0x6F, 0x69, 0x66]

        static let fileHeaderSize = 8                                   // magic[4] + samples[4]
        static let frameHeaderSize = 8                                  // channels[1] + samplerate[3] + fsamples[2] + fsize[2]
        static let lmsStateSizePerChannel = 16                          // history -> weights
        static let sliceSize = 8                                        // 64 bits slice

        static let sliceSamples = 20                                    // 逐樣本編碼核心迴圈（20 次）
        static let slicesPerFrame = 256
        static let maxSamplesPerFrame = sliceSamples * slicesPerFrame   // 最多的取樣大小 => 5120

        static let streamingSamples: UInt32 = 0                         // 串流 / 一般檔案用的 samples 標記

        static let maxChannels: UInt8 = 255
        static let maxSampleRate: UInt32 = 0x00FF_FFFF                  // 24-bit max: 16_777_215
        static let maxSamples: UInt32 = UInt32.max
        
        static let scaleFactorRange = 0..<16                            // QOA 規範：固定 16 種量化精度 (sf_quant ∈ [0,15])
        static let residualCodesRange = 0..<8                           // QOA 規範：9 碼本中的前 8 個殘差碼 (0-7)
        static let lmsHistorySize = 0..<4                               // QOA 規範：LMS 預測器歷史緩衝區大小
    }
}

// MARK: - QOA 其它相關常數
extension WWQOA {
    
    /// 位元欄位與 Mask（可依需要擴展）
    enum BitMask {
        
        static let sfQuantBits: UInt8 = 4                               // Scalefactor quantization 欄位：4 bits
        static let sfQuantShift: UInt8 = 60
        static let sfQuantMask: UInt64 = 0xF000_0000_0000_0000
        
        static let residualBits: UInt8 = 3                              // 每個 residual 用 3 bits 表示
        static let residualMask: UInt8  = 0x07
        
        static let sliceResidualCount = 20                              // 一個 slice 有 20 個 residual
    }
    
    /// 查表與演算法相關常數
    enum LookupTable {
        
        /// 反量化 table：index 0~7 對應 8 個 3-bit residuals
        /// 0.75, -0.75, 2.5, -2.5, 4.5, -4.5, 7.0, -7.0
        static let dequant: [Double] = [
            0.75, -0.75, 2.5, -2.5,
            4.5, -4.5, 7.0, -7.0
        ]

        /// 量化時用的權重表（可用於 `qoa_quant_tab` 的概念，但可以依你演算法調整）
        static let quantWeights: [Double] = [
            -7.0, -5.5, -4.5, -3.5,
            -2.5, -1.5, -0.75, 0.0,
            0.75,  1.5,  2.5,  3.5,
            4.5,  5.5,  7.0
        ]
    }

    /// 用於 LMS 逼近與 rounding 的常數
    enum LMS {
        static let lmsShift: Int = 13                                   // QOA LMS 的 shift 量：把 weights * history 的結果右移 13 位
        static let deltaShift: Int = 4                                  // weight update 的 delta shift: residual >> 4
        static let maxInt16: Int32 =  32_767                            // Int16.max
        static let minInt16: Int32 = -32_768                            // Int16.min
    }
    
    /// 用於 slice / frame 結構檢查的輔助常數
    enum FrameLayout {
        
        static let maxSlicesPerChannel = Constant.slicesPerFrame        // 每個 frame 最多可以有的 slices per channel
        static let maxSamplesPerChannel = Constant.maxSamplesPerFrame   // 一個 frame 最多的 samples per channel
    }
}

// MARK: - 錯誤訊息
extension WWQOA {

    /// 解碼「單一個 QOA frame」時可能發生的錯誤。
    enum FrameDecodeError: Error {

        case insufficientData                                           // 資料不夠，無法讀取完整的 frame header 或 LMS / slice 資料。
        case invalidChannelCount                                        // header 裡的聲道數超出有效範圍（例如 0 或太大）。
        case invalidSampleRate                                          // header 裡的 sampleRate 不在有效範圍（例如 0 或超過 24 bit 限制）。
        case invalidSamplesPerChannel                                   // header 裡的 samplesPerChannel 無效（例如 0 或超過 16 bit 限制）。
        case invalidFrameSize                                           // header 裡的 frameSize 無效或與實際計算不符。
        case invalidSliceLayout                                         // slice 的數量或排列不符合規格（例如 slice 數量無法對應到實際 samplesPerChannel）。
        case trailingFrameDataMismatch                                  // frame 裡實際解碼出的樣本數與 header 聲稱的數量不符（可能有 trailing garbage 或封包錯亂）。
    }
    
    /// 解碼「整個 QOA 檔案」時可能發生的錯誤。
    enum FileDecodeError: Error {

        case insufficientData                                           // 檔案資料不夠，無法讀取完整的檔案 header 或至少一個 frame。
        case invalidMagic                                               // 檔案 header 的 magic 不符（例如不是 "qoaf"）。
        case noFrames                                                   // 檔案裡沒有任何有效的 frame（可能是 header 正確但內容為空）。
        case inconsistentStaticFileChannels                             // 從多個 frame 解碼後，發現聲道數不一致（例如有的 frame 是 1 聲道，有的是 2 聲道，但 header 標示為 static file）。
        case inconsistentStaticFileSampleRate                           // 從多個 frame 解碼後，發現 sampleRate 不一致（但規格要求 static file 必須固定 sampleRate）。
        case frameDecodeFailed                                          // 某一個 frame 被 `WWQOA.FrameDecoder` 解碼失敗（例如 `FrameDecodeError`）。
        case sampleCountMismatch                                        // 解碼後累計的樣本數與 header 裡的總樣本數不一致（可能封包損壞或 streaming 標記與實際長度衝突）。
    }
}

// MARK: - WWQOA.FrameLayout
extension WWQOA.FrameLayout {
    
    /// 一個 frame header 加上所有 channel LMS 狀態的最小大小：
    /// frameHeaderSize + channels * lmsStateSizePerChannel
    /// (實際大小會再加 2 * channels * sliceCount)
    static func minimumFrameSize(channels: Int) -> Int {
        WWQOA.Constant.frameHeaderSize + channels * WWQOA.Constant.lmsStateSizePerChannel
    }
}

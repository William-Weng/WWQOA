//
//  SliceEncoder.swift
//  WWQOA
//
//  Created by William.Weng on 2026/04/20.
//
//  [Int16] 長度 ≤20 → pad 到固定20 → 試遍 16種 sfQuant → 選最佳 → EncodedSlice(64bits)
//     ↑                    ↑                 ↑                       ↓
//  原始 PCM             標準化長度         暴力最佳化              3.2 bits/sample
//
//  1. LMS 預測：用前 4 樣本預測當前 → 誤差極小
//  2. 量化：sfQuant 控制精度 (0-15 → 粗到精)
//  3. 算術編碼：64 bits 打包符號序列
//  4. 暴力選優：16 種精度中選「性價比最高」

import Foundation

// MARK: - 切片編碼器
extension WWQOA.SliceEncoder {
    
    /// QOA slice 壓縮：20 個 Int16 → 8 bytes (64 bits)
    /// - Parameters:
    ///   - samples: 最多 20 個 samples，不足會自動補 0 直到 20 個
    ///   - lms: 進入此 slice 前的 LMS 狀態
    /// - Returns: 編碼結果，包含 packed 64-bit slice 與更新後 LMS
    func encode(_ samples: [Int16], lms: WWQOA.LMSState) -> WWQOA.EncodedSlice {
        
        precondition(samples.count <= WWQOA.Constant.sliceSamples, "A QOA slice can hold at most 20 samples.")

        let paddedSamples = samples + Array(repeating: 0, count: WWQOA.Constant.sliceSamples - samples.count)   // [s0,s1,s2,...,s15] → [s0,s1,s2,...,s15,0,0,0,0,0] (固定20)

        var bestCandidate: WWQOA.EncodedSlice?

        for sfQuant in WWQOA.Constant.scaleFactorRange {
            
            let candidate = encodeSliceWithScalefactor(paddedSamples, sfQuant: UInt8(sfQuant), startLMS: lms, originalCount: samples.count)
            
            if let currentBest = bestCandidate {
                if (candidate.error < currentBest.error) { bestCandidate = candidate }
            } else {
                bestCandidate = candidate
            }
        }

        return bestCandidate!
    }
    
    /// QOA slice 解碼器：64-bit 封包 → PCM 樣本序列
    /// **完美對稱於編碼**：逆向執行「熵解碼 → 去量化 → LMS 重建」
    /// - 無損還原：packedValue 經過相同數學運算 → 原始重建樣本
    /// - Parameters:
    ///   - packedValue: 64-bit 壓縮封包（來自 QOA 檔案）
    ///   - lms: 起始 LMS 狀態（跨 slice 連續性）
    ///   - sampleCount: 實際樣本數（末尾可能零填充）
    /// - Returns: 解碼後 PCM + 更新後 LMS 狀態
    func decode(_ packedValue: UInt64, lms: WWQOA.LMSState, sampleCount: Int = WWQOA.Constant.sliceSamples) -> WWQOA.DecodedSlice {
        
        precondition(sampleCount >= 0 && sampleCount <= WWQOA.Constant.sliceSamples)

        let sfQuant = Int((packedValue >> WWQOA.BitMask.sfQuantShift) & 0xF)
        let scalefactor = dequantizedScalefactor(sfQuant)
        
        var currentLMS = lms
        var output: [Int16] = []
        
        output.reserveCapacity(sampleCount)
        
        for index in 0..<WWQOA.Constant.sliceSamples {
            
            let shift = UInt64(57 - index * 3)
            let code = Int((packedValue >> shift) & 0x7)

            let residual = dequantizeResidual(code: code, scalefactor: scalefactor)
            let predicted = predict(currentLMS)
            let sample = (predicted + residual).clamp16()

            update(lms: &currentLMS, sample: Int32(sample), residual: residual)
            
            if (index < sampleCount) { output.append(sample) }
        }
        
        return .init(samples: output, endLMS: currentLMS)
    }
}

// MARK: - 編碼器邏輯
private extension WWQOA.SliceEncoder {

    /// QOA slice 單一量化精度編碼器（暴力選優的「候選者生成器」） => 固定 sfQuant 下，逐樣本編碼 → 計算總誤差 → 回傳完整 EncodedSlice
    /// - Parameters:
    ///   - paddedSamples: 固定 20 樣本（末尾零填充）
    ///   - sfQuant: 量化精度索引 (0-15)
    ///   - startLMS: slice 起始 LMS 預測器狀態
    ///   - originalCount: 原始樣本數（<20 用於誤差計算）
    /// - Returns: 完整編碼結果（供 16 選 1 比較）
    func encodeSliceWithScalefactor(_ paddedSamples: [Int16], sfQuant: UInt8, startLMS: WWQOA.LMSState, originalCount: Int) -> WWQOA.EncodedSlice {
        
        let scalefactor = dequantizedScalefactor(Int(sfQuant))
        
        var totalError: Int64 = 0
        var codes: [UInt8] = Array(repeating: 0, count: WWQOA.Constant.sliceSamples)
        var reconstructed: [Int16] = Array(repeating: 0, count: WWQOA.Constant.sliceSamples)
        var currentLMS = startLMS
        
        for index in 0..<WWQOA.Constant.sliceSamples {
            
            let original = Int32(paddedSamples[index])
            let best = bestResidualCode(sample: original, lms: currentLMS, scalefactor: scalefactor)
            
            codes[index] = best.code
            reconstructed[index] = best.sample
            
            if (index < originalCount) {
                let diff = Int64(original) - Int64(best.sample)
                totalError += diff.square()
            }
            
            update(lms: &currentLMS, sample: Int32(best.sample), residual: best.residual)
        }
        
        let packed = packSlice(sfQuant: sfQuant, codes: codes)

        return .init(sfQuant: sfQuant, codes: codes, packedValue: packed, reconstructed: Array(reconstructed.prefix(originalCount)), error: totalError, endLMS: currentLMS)
    }
    
    /// 🔥 QOA 殘差量化核心：9 碼本暴力選優（0-8）
    /// 從 LMS 預測值出發，試遍 9 種殘差碼 → 選重建誤差最小的
    /// - Parameters:
    ///   - sample: 原始樣本 (Int32)
    ///   - lms: 當前 LMS 預測器狀態
    ///   - scalefactor: 量化精度 (1-4096，決定殘差範圍)
    /// - Returns: 最佳殘差碼及其重建值、誤差
    func bestResidualCode( sample: Int32, lms: WWQOA.LMSState, scalefactor: Int32) -> WWQOA.ResidualChoice {
        
        let predicted = predict(lms)
        
        var bestChoice: WWQOA.ResidualChoice?
        
        for code in WWQOA.Constant.residualCodesRange {
            
            let residual = dequantizeResidual(code: code, scalefactor: scalefactor)
            let reconstructed = (predicted + residual).clamp16()
            let diff = Int64(sample) - Int64(reconstructed)
            let error = diff.square()
            
            let choice = WWQOA.ResidualChoice(code: UInt8(code), sample: reconstructed, residual: residual, error: error)
            
            if let currentBest = bestChoice {
                if (choice.error < currentBest.error) { bestChoice = choice }
            } else {
                bestChoice = choice
            }
        }

        return bestChoice!
    }
}

// MARK: - 編碼打包
private extension WWQOA.SliceEncoder {

    /// QOA 算術編碼打包：將符號序列壓成 64-bit 整數 => 位元組佈局：sfQuant(4bits) + 20×3bits codes = 64 bits 精準無浪費
    /// - Parameters:
    ///   - sfQuant: 量化精度 (4 bits, 0-15)
    ///   - codes: 20 個殘差碼 (3 bits 每個, 0-7)
    /// - Returns: 64-bit 壓縮封包，直接寫入 QOA 檔案
    func packSlice(sfQuant: UInt8, codes: [UInt8]) -> UInt64 {
        
        precondition(codes.count == WWQOA.Constant.sliceSamples)

        var value: UInt64 = 0
        
        /// 1. sfQuant 置頂：位 63-60（最顯著位）
        /// 佈局：[sfQuant][code19][code18]...[code0]
        value = UInt64(sfQuant & 0x0F) << UInt64(WWQOA.BitMask.sfQuantShift)
        
        /// 2. 20 個 3-bit 碼，從高位到低位填充
        /// code19: bit 59-57, code18: bit 56-54, ..., code0: bit 2-0
        for index in 0..<WWQOA.Constant.sliceSamples {  // i=0 → code19, i=19 → code0
            let shift = UInt64(57 - index * 3)  // 59→57→54→...→2→0
            value |= UInt64(codes[index] & 0x07) << shift  // 3-bit 遮罩 + 左移
        }
        
        return value
    }
}

// MARK: - QOA的數學魔法
private extension WWQOA.SliceEncoder {
    
    /// QOA 規範：將量化索引 sf_quant 反量化為 scalefactor => `sf = round((sf_quant + 1)^2.75)` , `sf_quant ∈ [0,15]` → `scalefactor ∈ [1, 4096]`
    /// - Parameters:
    ///   - sfQuant: 量化索引 (0=最粗, 15=最精，QOA 規範固定 16 種)
    /// - Returns: 反量化後的 scalefactor (Int32)
    func dequantizedScalefactor(_ sfQuant: Int) -> Int32 {
        let value = pow(Double(sfQuant + 1), 2.75)
        return Int32(value.qoaRound())
    }
    
    /// 殘差去量化：3-bit 碼 → 實際殘差值 => QOA 規格核心：9 個碼本 × 動態 scalefactor
    /// - Parameters:
    ///   - code: Int
    ///   - scalefactor: Int32
    /// - Returns: Int32
    func dequantizeResidual(code: Int, scalefactor: Int32) -> Int32 {
        
        let base = WWQOA.LookupTable.dequant[code]  // 碼本查表 [-8, -3, -2, -1, 0, 1, 2, 3, 4]
        let scaled = Double(scalefactor) * base     // 動態縮放
        
        return Int32(scaled.qoaRound())             // QOA 規格四捨五入
    }
    
    /// QOA LMS 預測器：用前 4 個樣本線性預測當前值 => 公式：`prediction = Σ(history[i] * weights[i]) >> lmsShift`
    /// - Parameter lms: WWQOA.LMSState
    /// - Returns: Int32
    func predict(_ lms: WWQOA.LMSState) -> Int32 {
        var prediction: Int32 = 0
        
        for index in WWQOA.Constant.lmsHistorySize {
            prediction += lms.history[index] * lms.weights[index]   // 加權和
        }
        
        return prediction >> Int32(WWQOA.LMS.lmsShift)              // 固定右移：等同除法，防止溢位 + 控制預測強度
    }
    
    /// 🔥 LMS 預測器適應性更新：學習當前樣本，準備下次預測
    /// - 動態調整權重：根據殘差符號更新 4 個係數
    /// - 滑動歷史窗：最新樣本進來 → 最舊樣本移出
    /// - QOA 規範：符號梯度下降（SGD）簡化版
    /// - Parameters:
    ///   - lms: LMSState（權重 + 歷史緩衝）
    ///   - sample: 當前重建樣本（用於 history 更新）
    ///   - residual: 量化後殘差（用於權重學習）
    func update(lms: inout WWQOA.LMSState, sample: Int32, residual: Int32) {
        
        /// 1. 計算學習率：殘差 >> deltaShift（等同除以 2^deltaShift）
        /// - deltaShift 固定值，通常 = 8
        /// - 作用：控制學習速度，避免權重震盪
        let delta = residual >> Int32(WWQOA.LMS.deltaShift)
        
        /// 2. 符號梯度下降：4 個權重同時更新
        /// - history[i] > 0 → 權重 +delta（加強正相關）
        /// - history[i] < 0 → 權重 -delta（加強負相關）
        for index in WWQOA.Constant.lmsHistorySize {
            lms.weights[index] += (lms.history[index] < 0) ? -delta : delta
        }
        
        /// 3. 滑動歷史窗：FIFO 隊列（4 階）
        /// 最舊 → 新 歷史移位，最新樣本進入
        lms.history[0] = lms.history[1]  // s[n-4] = s[n-3]
        lms.history[1] = lms.history[2]  // s[n-3] = s[n-2]
        lms.history[2] = lms.history[3]  // s[n-2] = s[n-1]
        lms.history[3] = sample          // s[n-1] = 重建樣本
    }
}

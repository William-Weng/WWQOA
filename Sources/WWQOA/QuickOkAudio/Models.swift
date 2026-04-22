//
//  Types.swift
//  WWQOA
//
//  Created by William.Weng on 2026/04/20.
//

import Foundation

public extension WWQOA {

    struct FileEncoder {
        let frameEncoder = WWQOA.FrameEncoder()
    }
    
    struct FileDecoder {
        let frameDecoder = WWQOA.FrameDecoder()
    }
}

extension WWQOA {
    
    struct FrameEncoder {
        let sliceEncoder = WWQOA.SliceEncoder()
    }
    
    struct FrameDecoder {}
    struct SliceEncoder {}
    struct WavEncoder {}
    
    enum Debug {}
}

public extension WWQOA {

    /// 整個 QOA 檔案的編碼資訊
    struct FileEncodeInformation: Equatable {
        
        public let count: Int
        public let frameCount: Int
        public let channels: Int
        public let sampleRate: Int
        
        /// 初始化
        /// - Parameters:
        ///   - count: 二進位資料大小
        ///   - frameCount: 這個 QOA 檔案被切成的 frame 數量（至少一個 frame）
        ///   - channels: 聲道數（例如：1 = mono, 2 = stereo）
        ///   - sampleRate: 取樣率（例如：44100 Hz）
        init(count: Int, frameCount: Int, channels: Int, sampleRate: Int) {
            self.count = count
            self.frameCount = frameCount
            self.channels = channels
            self.sampleRate = sampleRate
        }
    }
    
    /// 整個 QOA 檔案的編碼結果。記錄編碼後的完整二進位資料、frame／音訊 metadata，以及編碼結束時的 LMS 狀態，用於後續分析或串接。
    struct FileEncodeResult: Equatable {
        
        public let data: Data
        public let frameCount: Int
        public let channels: Int
        public let sampleRate: Int
        public let samplesPerChannelInHeader: UInt32
        public let actualSamplesPerChannel: Int
        public let finalLMSStates: [LMSState]
        
        /// 建立一個完整的 QOA 檔案編碼結果。
        /// 會檢查基本限制，確保修訂的結果符合 QOA 規格。
        /// - Parameters:
        ///   - data: 完整 .qoa 二進位資料
        ///   - frameCount: 這個 QOA 檔案被切成的 frame 數量（至少一個 frame）
        ///   - channels: 聲道數（例如：1 = mono, 2 = stereo）
        ///   - sampleRate: 取樣率（例如：44100 Hz）
        ///   - samplesPerChannelInHeader: 寫入到 QOA 檔案 header 的「每聲道總樣本數」，用於格式描述，可能與 `actualSamplesPerChannel` 不同（例如 streaming 模式）
        ///   - actualSamplesPerChannel: 實際有效音訊的「每聲道樣本數」，也就是實際編碼的長度，用來比對與 header 標示的總長度是否一致，或處理尾段補洞的邏輯
        ///   - finalLMSStates: 編碼結束後的 LMS 狀態陣列（每聲道一個），可用於：串接下一個 QOA 檔案時，作為下一個 `WWQOA.FileEncoder.encodeFile(_:)` 的初始 LMS。調試與分析 LMS 模型的適應過程。
        init(data: Data, frameCount: Int, channels: Int, sampleRate: Int, samplesPerChannelInHeader: UInt32, actualSamplesPerChannel: Int, finalLMSStates: [LMSState]) {
            
            precondition(frameCount > 0, "QOA file must contain at least one frame.")
            precondition(channels > 0 && channels <= Int(WWQOA.Constant.maxChannels))
            precondition(sampleRate > 0 && sampleRate <= Int(WWQOA.Constant.maxSampleRate))
            precondition(actualSamplesPerChannel > 0)
            precondition(finalLMSStates.count == channels, "finalLMSStates count must match channel count.")

            self.data = data
            self.frameCount = frameCount
            self.channels = channels
            self.sampleRate = sampleRate
            self.samplesPerChannelInHeader = samplesPerChannelInHeader
            self.actualSamplesPerChannel = actualSamplesPerChannel
            self.finalLMSStates = finalLMSStates
        }
    }
    
    /// QOA 使用的 [LMS（Least Mean Squares）](https://zh.wikipedia.org/zh-tw/最小均方滤波器)預測器狀態。用來做「有狀態的線性預測」，在編碼／解碼時維持連續的「預測」模型。
    struct LMSState: Equatable {
        
        static let zero = LMSState()    // 一個全零的 LMS 狀態，常用於「初始化」或「重設」。
        
        var history: [Int32]            // 預測器的歷史樣本（history buffer）。通常是最近的 4 個已解碼／已編碼樣本，用來做下一個樣本的預測。
        var weights: [Int32]            // 預測器的權重（coefficients）。4 個 weight 對應 4 個歷史樣本，用來計算線性預測：y = sum(weight_i * history_i)。

        /// 建立一個 LMS 狀態。保証：history 與 weights 都必須是 4 個元素，符合 QOA 規格。
        /// - Parameters:
        ///   - history: 歷史樣本陣列，預設為 [0, 0, 0, 0]
        ///   - weights: 權重陣列，預設為 [0, 0, 0, 0]
        init(history: [Int32] = [0, 0, 0, 0], weights: [Int32] = [0, 0, 0, 0]) {
            
            precondition(history.count == 4, "QOA LMS history must contain 4 values.")
            precondition(weights.count == 4, "QOA LMS weights must contain 4 values.")
            
            self.history = history
            self.weights = weights
        }
    }

    // MARK: - Frame Types

    /// Frame encoder 的輸入
    ///
    /// - interleavedSamples: interleaved PCM，例如 stereo 為 L0,R0,L1,R1...
    /// - channels: 1...255
    /// - sampleRate: 1...16777215
    struct FrameInput: Equatable {
        
        let interleavedSamples: [Int16]
        let channels: Int
        let sampleRate: Int

        public init(interleavedSamples: [Int16], channels: Int, sampleRate: Int) {
            precondition(channels > 0 && channels <= Int(WWQOA.Constant.maxChannels), "QOA channels must be in 1...255.")
            precondition(sampleRate > 0 && sampleRate <= Int(WWQOA.Constant.maxSampleRate), "QOA sampleRate must be in 1...16777215.")
            precondition(interleavedSamples.count % channels == 0, "Interleaved sample count must be divisible by channels.")

            self.interleavedSamples = interleavedSamples
            self.channels = channels
            self.sampleRate = sampleRate
        }

        var samplesPerChannel: Int {
            interleavedSamples.count / channels
        }

        var slicesPerChannel: Int {
            Int(ceil(Double(samplesPerChannel) / Double(WWQOA.Constant.sliceSamples)))
        }

        var isValidFrameLength: Bool {
            samplesPerChannel > 0 && samplesPerChannel <= WWQOA.Constant.maxSamplesPerFrame
        }
    }

    /// frame header 對應的 Swift 模型
    ///
    /// 規格欄位：
    /// - num_channels: uint8
    /// - samplerate: uint24
    /// - fsamples: uint16
    /// - fsize: uint16
    struct FrameHeader: Equatable {
        
        public let channels: Int
        public let sampleRate: Int
        public let samplesPerChannel: Int
        public let frameSize: Int

        init(channels: Int, sampleRate: Int, samplesPerChannel: Int, frameSize: Int) {
            
            precondition(channels > 0 && channels <= Int(WWQOA.Constant.maxChannels))
            precondition(sampleRate > 0 && sampleRate <= Int(WWQOA.Constant.maxSampleRate))
            precondition(samplesPerChannel > 0 && samplesPerChannel <= 0xFFFF)
            precondition(frameSize > 0 && frameSize <= 0xFFFF)

            self.channels = channels
            self.sampleRate = sampleRate
            self.samplesPerChannel = samplesPerChannel
            self.frameSize = frameSize
        }

        var slicesPerChannel: Int {
            Int(ceil(Double(samplesPerChannel) / Double(WWQOA.Constant.sliceSamples)))
        }
    }

    /// 單一 frame 的編碼結果
    struct FrameEncodeResult: Equatable {
        
        public let data: Data
        public let header: FrameHeader
        public let slicesPerChannel: Int
        public let startLMSStates: [LMSState]
        public let endLMSStates: [LMSState]

        public init(
            data: Data,
            header: FrameHeader,
            slicesPerChannel: Int,
            startLMSStates: [LMSState],
            endLMSStates: [LMSState]
        ) {
            precondition(startLMSStates.count == header.channels, "startLMSStates count must match channel count.")
            precondition(endLMSStates.count == header.channels, "endLMSStates count must match channel count.")

            self.data = data
            self.header = header
            self.slicesPerChannel = slicesPerChannel
            self.startLMSStates = startLMSStates
            self.endLMSStates = endLMSStates
        }
    }

    /// 單一 frame 的解碼結果
    struct FrameDecodeResult: Equatable {
        
        public let header: FrameHeader
        public let interleavedSamples: [Int16]
        public let planarSamples: [[Int16]]
        public let startLMSStates: [LMSState]
        public let endLMSStates: [LMSState]
        public let bytesRead: Int

        init(
            header: FrameHeader,
            interleavedSamples: [Int16],
            planarSamples: [[Int16]],
            startLMSStates: [LMSState],
            endLMSStates: [LMSState],
            bytesRead: Int
        ) {
            precondition(planarSamples.count == header.channels, "planarSamples count must match channel count.")
            precondition(startLMSStates.count == header.channels, "startLMSStates count must match channel count.")
            precondition(endLMSStates.count == header.channels, "endLMSStates count must match channel count.")

            self.header = header
            self.interleavedSamples = interleavedSamples
            self.planarSamples = planarSamples
            self.startLMSStates = startLMSStates
            self.endLMSStates = endLMSStates
            self.bytesRead = bytesRead
        }
    }
    
    /// 整個 QOA 檔案的輸入參數結構。
    /// 用來描述一段 interleaved PCM 音訊，準備送給 `WWQOA.FileEncoder.encodeFile(_:)` 做編碼。
    /// 內容包含音訊資料、聲道數、取樣率，以及總樣本數資訊。
    struct FileEncodeInput: Equatable {
        
        public let interleavedSamples: [Int16]
        public let channels: Int
        public let sampleRate: Int
        public let totalSamplesPerChannel: UInt32  // 檔案 header 裡記載的「每聲道總樣本數」，類型為 UInt32。用於 QOA 檔案 header，不一定要是實際有效長度（例如 streaming 模式會用固定值）。
        
        var actualSamplesPerChannel: Int { calculateActualSamplesPerChannel() }

        /// 是否屬於「streaming 模式」。
        /// 當 `totalSamplesPerChannel` 設定為 `WWQOA.Constant.streamingSamples` 時，表示這是個沒有明確終點的串流，
        /// 解碼端會用這個標記來處理 potentially 無限的 QOA stream。
        var isStreaming: Bool {
            totalSamplesPerChannel == WWQOA.Constant.streamingSamples
        }

        /// 由此輸入會產生的「總 frame 數」。
        /// 會依 `actualSamplesPerChannel` 與 `WWQOA.Constant.maxSamplesPerFrame` 上取整得到。
        /// 供 API 使用者快速預估 frame 數量。
        var frameCount: Int {
            Int(ceil(Double(actualSamplesPerChannel) / Double(WWQOA.Constant.maxSamplesPerFrame)))
        }
        
        var totalFrames: Int { calculateTotalFrames() }
        
        /// 建立一個一般 QOA 檔案的輸入結構。會自動由 `interleavedSamples.count` 計算 `totalSamplesPerChannel`。
        /// - Parameters:
        ///   - interleavedSamples: interleaved PCM 樣本陣列（例如：雙聲道為 [L0, R0, L1, R1, ...]）
        ///   - channels: 聲道數（例如：1 = Mono, 2 = Stereo）
        ///   - sampleRate: 取樣率（例如：44100 Hz）
        public init(interleavedSamples: [Int16], channels: Int, sampleRate: Int) {
            
            // 保証：聲道數在 QOA 規格範圍內（1~255）
            precondition(channels > 0 && channels <= Int(WWQOA.Constant.maxChannels),
                         "QOA channels must be in 1...255.")

            // 保証：取樣率在規格範圍內（1~16777215 Hz）
            precondition(sampleRate > 0 && sampleRate <= Int(WWQOA.Constant.maxSampleRate),
                         "QOA sampleRate must be in 1...16777215.")

            // 保証：interleaved 樣本總數可以整除聲道數，否則聲道對齊會出錯
            precondition(interleavedSamples.count % channels == 0,
                         "Interleaved sample count must be divisible by channels.")

            let samplesPerChannel = interleavedSamples.count / channels

            // 保証：每聲道至少一個樣本，否則無法構成一個有效的 QOA 檔案
            precondition(samplesPerChannel > 0,
                         "QOA file must contain at least one sample per channel.")

            // 保証：每聲道樣本數不會超出 UInt32 範圍（header 用 UInt32 存）
            precondition(samplesPerChannel <= Int(UInt32.max),
                         "samplesPerChannel exceeds UInt32 range.")

            self.interleavedSamples = interleavedSamples
            self.channels = channels
            self.sampleRate = sampleRate
            self.totalSamplesPerChannel = UInt32(samplesPerChannel)
        }

        /// 建立一個「串流模式」的 QOA 輸入。
        /// 用於沒有明確總長度、以 streaming 模式封裝的 QOA，header 裡的 `totalSamplesPerChannel` 會被標為 streaming 專用常數。
        ///
        /// - Parameters:
        ///   - interleavedSamples: interleaved PCM 樣本（目前這一段的資料）
        ///   - channels: 聲道數
        ///   - sampleRate: 取樣率（Hz）
        ///
        /// 注意：串流模式下，`totalSamplesPerChannel` 並非真實長度，而是用來標記「這是串流」。
        init(streamingInterleavedSamples interleavedSamples: [Int16], channels: Int, sampleRate: Int) {
            // 保証：聲道數在 QOA 規格範圍內
            precondition(channels > 0 && channels <= Int(WWQOA.Constant.maxChannels),
                         "QOA channels must be in 1...255.")

            // 保証：取樣率在規格範圍內
            precondition(sampleRate > 0 && sampleRate <= Int(WWQOA.Constant.maxSampleRate),
                         "QOA sampleRate must be in 1...16777215.")

            // 保証：interleaved 樣本總數可整除聲道數
            precondition(interleavedSamples.count % channels == 0,
                         "Interleaved sample count must be divisible by channels.")

            let samplesPerChannel = interleavedSamples.count / channels

            // 保証：每聲道至少一個樣本
            precondition(samplesPerChannel > 0,
                         "QOA file must contain at least one sample per channel.")

            self.interleavedSamples = interleavedSamples
            self.channels = channels
            self.sampleRate = sampleRate
            // 用 streaming 專用常數標示「這是串流」，解碼端會特殊處理
            self.totalSamplesPerChannel = WWQOA.Constant.streamingSamples
        }
    }
    
    /// 整個 QOA 檔案的解碼資訊
    struct FileDecodeInformation: Equatable {
        
        public let count: Int
        public let channels: Int
        public let sampleRate: Int
        
        /// 初始化
        /// - Parameters:
        ///   - count: 檔案大小
        ///   - channels: 聲道數
        ///   - sampleRate: 採樣率
        init(count: Int, channels: Int, sampleRate: Int) {
            self.count = count
            self.channels = channels
            self.sampleRate = sampleRate
        }
    }
    
    /// 整個 QOA 檔案的解碼結果
    struct FileDecodeResult: Equatable {
        
        public let samplesPerChannelInHeader: UInt32
        public let frameHeaders: [FrameHeader]
        public let interleavedSamples: [Int16]
        public let planarSamples: [[Int16]]
        public let channels: Int
        public let sampleRate: Int

        /// 指定初級建構器，執行完整性驗證
        /// - Parameters:
        ///   - samplesPerChannelInHeader: QOA file header 中的總樣本數
        ///   - frameHeaders: 解碼出的所有 frame headers
        ///   - interleavedSamples: 交錯排列的 PCM samples
        ///   - planarSamples: 分聲道排列的 PCM samples
        ///   - channels: 聲道數
        ///   - sampleRate: 採樣率
        /// - Throws: `preconditionFailure` 當參數不符合 QOA 規格時
        init(samplesPerChannelInHeader: UInt32, frameHeaders: [FrameHeader], interleavedSamples: [Int16], planarSamples: [[Int16]], channels: Int, sampleRate: Int) {
            
            precondition(!frameHeaders.isEmpty, "A valid QOA file must contain at least one frame.")
            precondition(channels > 0 && channels <= Int(WWQOA.Constant.maxChannels))
            precondition(sampleRate > 0 && sampleRate <= Int(WWQOA.Constant.maxSampleRate))
            precondition(planarSamples.count == channels, "planarSamples count must match channel count.")
            
            self.samplesPerChannelInHeader = samplesPerChannelInHeader
            self.frameHeaders = frameHeaders
            self.interleavedSamples = interleavedSamples
            self.planarSamples = planarSamples
            self.channels = channels
            self.sampleRate = sampleRate
        }
    }
}

// MARK: - 一般模型
extension WWQOA {
    
    /// QOA 殘差碼本單元：bestResidualCode() 的試算結果
    struct ResidualChoice {
        
        let code: UInt8                 // 殘差碼本索引 (0-7)，QOA 規範固定 9 種碼 => 0 = 0, 1 = ±1×sf, 2 = ±3×sf, ... 指數增長
        let sample: Int16               // 重建樣本值：predicted + residual，經 clamp16() 限制 Int16 範圍
        let residual: Int32             // 解量化後的實際殘差：dequantizeResidual(code, scalefactor)
        let error: Int64                // 平方重建誤差：(原始 - sample)^2，貪婪選擇依據 => 最小者勝出，決定此 slice 最終 code
    }
    
    /// QOA slice 完整編碼結果：單一 sfQuant 下的壓縮輸出，16 種量化精度試算後的候選者，供誤差最小者選用
    struct EncodedSlice: Equatable {
        
        let sfQuant: UInt8
        let codes: [UInt8]
        let packedValue: UInt64
        let reconstructed: [Int16]
        let error: Int64
        let endLMS: LMSState
        
        /// 初始化
        /// - Parameters:
        ///   - sfQuant: 量化精度索引 (0-15)，決定此 slice 的 scalefactor => sfQuant=0：最粗量化，sf=1 => sfQuant=15：最精量化，sf=4096
        ///   - codes: 20 個殘差碼：每個樣本對應的 3-bit 碼本索引 (0-8) => 由 bestResidualCode() 逐樣本選出 => 總計 20×3 = 60 bits + sfQuant 4 bits = 64 bits
        ///   - packedValue: 算術編碼後的壓縮封包：64 bits 固定長度 => 由 packSlice(sfQuant, codes) 產生
        ///   - reconstructed: 重建樣本序列：原始 PCM 經此 slice 解碼後的結果 => 用於品質驗證：(原始-reconstructed)^2 = error
        ///   - error: 總平方重建誤差：Σ(原始[i] - reconstructed[i])^2 => 16 選 1 的**唯一決策依據**：誤差最小者勝出
        ///   - endLMS: slice 結束時的 LMS 預測器狀態 => 傳遞給下一個 slice，實現跨 slice 連續預測
        init(sfQuant: UInt8, codes: [UInt8], packedValue: UInt64, reconstructed: [Int16], error: Int64, endLMS: LMSState) {
            
            precondition(codes.count == WWQOA.Constant.sliceSamples, "A QOA slice must contain exactly 20 residual codes.")
            
            self.sfQuant = sfQuant
            self.codes = codes
            self.packedValue = packedValue
            self.reconstructed = reconstructed
            self.error = error
            self.endLMS = endLMS
        }
    }
    
    /// QOA slice 解碼結果：PCM 樣本 + LMS 連續狀態，跨 slice 傳遞的「橋樑」結構，保證無縫連接
    struct DecodedSlice: Equatable {
        
        let samples: [Int16]
        let endLMS: LMSState
        
        /// 建構器：嚴格驗證 slice 大小
        /// - Parameters:
        ///   - samples: 解碼後 PCM 樣本序列 => 長度：0-20（末尾 slice 可能短）, 範圍：[-32768, 32767] Int16
        ///   - endLMS: slice 結束時的 LMS 狀態 => 傳遞給下一個 slice，實現時間連續預測
        init(samples: [Int16], endLMS: LMSState) {
            
            precondition(samples.count <= WWQOA.Constant.sliceSamples, "A decoded slice can contain at most 20 samples.")
            
            self.samples = samples
            self.endLMS = endLMS
        }
    }
    
    /// Data讀取工具
    struct ByteReader {
        
        let data: Data          // 要讀取的資料
        var offset: Int = 0     // 目前的偏移量
    }
}

// MARK: - 小工具
extension WWQOA.LMSState {
    
    /// 產生初始化Array
    /// - Parameter count: Int
    /// - Returns: [Self]
    static func zeroArray(count: Int) -> [Self] {
        return Array(repeating: zero, count: count)
    }
}

// MARK: - 小工具
extension WWQOA.FileEncodeResult {
    
    /// FileEncodeResult => FileEncodeInformation
    /// - Returns: FileEncodeInformation
    func information() -> WWQOA.FileEncodeInformation {
        return .init(count: data.count, frameCount: frameCount, channels: channels, sampleRate: sampleRate)
    }
}

// MARK: - 小工具
extension WWQOA.FileDecodeResult {
    
    /// FileDecodeResult => FileDecodeInformation
    /// - Parameter count: WAV的檔案大小
    /// - Returns: FileEncodeInformation
    func information(count: Int) -> WWQOA.FileDecodeInformation {
        return .init(count: count, channels: channels, sampleRate: sampleRate)
    }
}

// MARK: - 小工具
private extension WWQOA.FileEncodeInput {
    
    /// 依最大樣本數向上取整，得到總 frame 數
    /// - Returns: Int
    func calculateTotalFrames() -> Int {
        
        let maxFrameSamplesPerChannel = WWQOA.Constant.maxSamplesPerFrame
        let totalFrames = Int(ceil(Double(actualSamplesPerChannel) / Double(maxFrameSamplesPerChannel)))
        
        return totalFrames
    }
    
    /// 用來「先算出有幾段（每聲道總樣本數）」，是後面做 frame / slice 切分的長度依據 => 1000筆取樣 / 2聲道 = 500段
    /// - Returns: Int
    func calculateActualSamplesPerChannel() -> Int {
        return interleavedSamples.count / channels
    }
}


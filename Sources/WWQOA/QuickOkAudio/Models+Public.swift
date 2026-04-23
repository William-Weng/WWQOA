//
//  Models+Public.swift
//  WWQOA
//
//  Created by William.Weng on 2026/4/23.
//

import Foundation

// MARK: - 主要類型
public extension WWQOA {
    
    /// 整個 QOA 檔案的編碼資訊
    struct FileEncodeInformation: Equatable {
        public let count: Int                           // 二進位資料大小
        public let frameCount: Int                      // 這個 QOA 檔案被切成的 frame 數量（至少一個 frame）
        public let channels: Int                        // 聲道數（例如：1 = mono, 2 = stereo）
        public let sampleRate: Int                      // 取樣率（例如：44100 Hz）
    }
    
    /// 整個 QOA 檔案的編碼結果。記錄編碼後的完整二進位資料、frame／音訊 metadata，以及編碼結束時的 LMS 狀態，用於後續分析或串接。
    struct FileEncodeResult: Equatable {
        public let data: Data                           // 完整 .qoa 二進位資料
        public let frameCount: Int                      // 這個 QOA 檔案被切成的 frame 數量（至少一個 frame）
        public let channels: Int                        // 聲道數（例如：1 = mono, 2 = stereo）
        public let sampleRate: Int                      // 取樣率（例如：44100 Hz）
        public let samplesPerChannelInHeader: UInt32    // 寫入到 QOA 檔案 header 的「每聲道總樣本數」，用於格式描述，可能與 `actualSamplesPerChannel` 不同（例如 streaming 模式）
        public let actualSamplesPerChannel: Int         // 實際有效音訊的「每聲道樣本數」，也就是實際編碼的長度，用來比對與 header 標示的總長度是否一致，或處理尾段補洞的邏輯
        public let finalLMSStates: [LMSState]           // 編碼結束後的 LMS 狀態陣列（每聲道一個），可用於：串接下一個 QOA 檔案時，作為下一個 `WWQOA.FileEncoder.encodeFile(_:)` 的初始 LMS。調試與分析 LMS 模型的適應過程。
    }
    
    /// 整個 QOA 檔案的解碼資訊
    struct FileDecodeInformation: Equatable {
        public let count: Int                           // count: 檔案大小
        public let channels: Int                        // 聲道數（例如：1 = mono, 2 = stereo）
        public let sampleRate: Int                      // 取樣率（例如：44100 Hz）
    }
    
    /// 整個 QOA 檔案的解碼結果
    struct FileDecodeResult: Equatable {
        public let samplesPerChannelInHeader: UInt32    // QOA file header 中的總樣本數
        public let frameHeaders: [FrameHeader]          // 解碼出的所有 frame headers
        public let interleavedSamples: [Int16]          // 交錯排列的 PCM samples
        public let planarSamples: [[Int16]]             // 分聲道排列的 PCM samples
        public let channels: Int                        // 聲道數
        public let sampleRate: Int                      // 採樣率
    }
}

// MARK: - 子類型
public extension WWQOA {
    
    /// QOA 使用的 [LMS（Least Mean Squares）](https://zh.wikipedia.org/zh-tw/最小均方滤波器)預測器狀態。用來做「有狀態的線性預測」，在編碼／解碼時維持連續的「預測」模型。
    struct LMSState: Equatable {
        
        static let zero = LMSState()                    // 一個全零的 LMS 狀態，常用於「初始化」或「重設」。
        
        var history: [Int32]                            // 預測器的歷史樣本（history buffer）。通常是最近的 4 個已解碼／已編碼樣本，用來做下一個樣本的預測。
        var weights: [Int32]                            // 預測器的權重（coefficients）。4 個 weight 對應 4 個歷史樣本，用來計算線性預測：y = sum(weight_i * history_i)。

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
    
    /// QOA 檔案格式的 Frame Header Swift 模型，對應 QOA 規範中的 16 bytes frame header（magic + channels + sampleRate + samples + frameSize）。從二進制資料解析後的結構化表示，用於編解碼流程中的參數傳遞和驗證。
    struct FrameHeader: Equatable {
        
        public let channels: Int                        // 聲道數（1-255），對應 header bytes 2-3 => QOA 支援多聲道音頻，1 = 單聲道，2 = 立體聲
        public let sampleRate: Int                      // 取樣率（Hz），對應 header bytes 4-5 => QOA 固定支援 44100Hz/48000Hz，其他值保留為未來擴展
        public let samplesPerChannel: Int               // 每個聲道的樣本數，對應 header bytes 6-9（24-bit） => 決定本 frame 的音頻持續時間：`duration = samplesPerChannel / sampleRate`
        public let frameSize: Int                       // 整個 frame 的大小（bytes），對應 header bytes 10-13（24-bit） => 包含 header（16 bytes）+ payload，最大約 55KB

        var slicesPerChannel: Int { calculateSlicesPerChannel() }
    }
    
    /// 整個 QOA 檔案的輸入參數結構。
    /// 用來描述一段 interleaved PCM 音訊，準備送給 `WWQOA.FileEncoder.encodeFile(_:)` 做編碼。
    /// 內容包含音訊資料、聲道數、取樣率，以及總樣本數資訊。
    struct FileEncodeInput: Equatable {
        
        public let interleavedSamples: [Int16]
        public let channels: Int
        public let sampleRate: Int
        public let totalSamplesPerChannel: UInt32
        
        var actualSamplesPerChannel: Int { calculateActualSamplesPerChannel() }
        var isStreaming: Bool { checkIsStreaming() }
        var frameCount: Int { calculateFrameCount() }
        var totalFrames: Int { calculateTotalFrames() }
        
        /// 建立一個一般 QOA 檔案的輸入結構。會自動由 `interleavedSamples.count` 計算 `totalSamplesPerChannel`。
        /// - Parameters:
        ///   - interleavedSamples: interleaved PCM 樣本陣列（例如：雙聲道為 [L0, R0, L1, R1, ...]）
        ///   - channels: 聲道數（例如：1 = Mono, 2 = Stereo）
        ///   - sampleRate: 取樣率（例如：44100 Hz）
        public init(interleavedSamples: [Int16], channels: Int, sampleRate: Int) {
            
            let samplesPerChannel = interleavedSamples.count / channels
            
            precondition(channels > 0 && channels <= Int(WWQOA.Constant.maxChannels), "QOA channels must be in 1...255.")
            precondition(sampleRate > 0 && sampleRate <= Int(WWQOA.Constant.maxSampleRate), "QOA sampleRate must be in 1...16777215.")
            precondition(interleavedSamples.count % channels == 0, "Interleaved sample count must be divisible by channels.")
            precondition(samplesPerChannel > 0, "QOA file must contain at least one sample per channel.")
            precondition(samplesPerChannel <= Int(UInt32.max), "samplesPerChannel exceeds UInt32 range.")

            self.interleavedSamples = interleavedSamples
            self.channels = channels
            self.sampleRate = sampleRate
            self.totalSamplesPerChannel = UInt32(samplesPerChannel)
        }

        /// 建立一個「串流模式」的 QOA 輸入。用於沒有明確總長度、以 streaming 模式封裝的 QOA，header 裡的 `totalSamplesPerChannel` 會被標為 streaming 專用常數。注意：串流模式下，`totalSamplesPerChannel` 並非真實長度，而是用來標記「這是串流」。
        /// - Parameters:
        ///   - interleavedSamples: interleaved PCM 樣本（目前這一段的資料）
        ///   - channels: 聲道數
        ///   - sampleRate: 取樣率（Hz）
        init(streamingInterleavedSamples interleavedSamples: [Int16], channels: Int, sampleRate: Int) {
            
            let samplesPerChannel = interleavedSamples.count / channels
            
            precondition(channels > 0 && channels <= Int(WWQOA.Constant.maxChannels), "QOA channels must be in 1...255.")
            precondition(sampleRate > 0 && sampleRate <= Int(WWQOA.Constant.maxSampleRate), "QOA sampleRate must be in 1...16777215.")
            precondition(interleavedSamples.count % channels == 0, "Interleaved sample count must be divisible by channels.")
            precondition(samplesPerChannel > 0, "QOA file must contain at least one sample per channel.")

            self.interleavedSamples = interleavedSamples
            self.channels = channels
            self.sampleRate = sampleRate
            self.totalSamplesPerChannel = WWQOA.Constant.streamingSamples
        }
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
extension WWQOA.LMSState {
    
    /// 產生初始化Array
    /// - Parameter count: Int
    /// - Returns: [Self]
    static func zeroArray(count: Int) -> [Self] {
        return Array(repeating: zero, count: count)
    }
}

// MARK: - 小工具
private extension WWQOA.FrameHeader {
    
    /// 計算每個聲道所需的切片數（slices）=> QOA 核心演算法每個切片固定處理 `Constant.sliceSamples`（通常 192 個樣本）。使用 `ceil()` 確保最後一個不完整切片也能正確解碼。
    /// - Returns: Int
    func calculateSlicesPerChannel() -> Int {
        return Int(ceil(Double(samplesPerChannel) / Double(WWQOA.Constant.sliceSamples)))
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
    
    /// 是否屬於「streaming 模式」。當 `totalSamplesPerChannel` 設定為 `WWQOA.Constant.streamingSamples` 時，表示這是個沒有明確終點的串流，解碼端會用這個標記來處理 potentially 無限的 QOA stream。
    /// - Returns: Bool
    func checkIsStreaming() -> Bool {
        return totalSamplesPerChannel == WWQOA.Constant.streamingSamples
    }

    /// 由此輸入會產生的「總 frame 數」。會依 `actualSamplesPerChannel` 與 `WWQOA.Constant.maxSamplesPerFrame` 上取整得到。供 API 使用者快速預估 frame 數量。
    func calculateFrameCount() -> Int {
        return Int(ceil(Double(actualSamplesPerChannel) / Double(WWQOA.Constant.maxSamplesPerFrame)))
    }
}

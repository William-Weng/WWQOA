import Foundation
import WWByteReader

// MARK: - 公開函式
extension WWQOA.FrameDecoder {
    
    /// 解碼單一 QOA frame
    /// - Parameter data: 一個完整 frame 的 bytes（不是整個 qoa file）
    /// - Returns: 解碼後的 frame 資訊與 PCM
    func decodeFrame(_ data: Data) throws -> WWQOA.FrameDecodeResult {
        
        var reader = WWByteReader(data: data)
        
        let header = try readFrameHeader(from: &reader)
        let expectedFrameSize = calculateExpectedFrameSize(with: header)
        let slicesPerChannel = Int(ceil(Double(header.samplesPerChannel) / Double(WWQOA.Constant.sliceSamples)))
        
        if (expectedFrameSize != header.frameSize) { throw WWQOA.FrameDecodeError.invalidSliceLayout }
        
        var startLMSStates: [WWQOA.LMSState] = try readLMSStates(from: &reader, channels: header.channels)
        var planarSamples = emptyPlanarSamples(channels: header.channels, samplesPerChannel: slicesPerChannel)
        var currentLMSStates = startLMSStates
        
        for sliceIndex in 0..<slicesPerChannel {
            
            for channel in 0..<header.channels {
                
                let packedSlice = try reader.readUIntValue() as UInt64
                let remainingSamples = header.samplesPerChannel - sliceIndex * WWQOA.Constant.sliceSamples
                let sampleCount = min(WWQOA.Constant.sliceSamples, remainingSamples)
                let decoded = WWQOA.SliceEncoder().decode( packedSlice, lms: currentLMSStates[channel], sampleCount: sampleCount)
                
                planarSamples[channel].append(contentsOf: decoded.samples)
                currentLMSStates[channel] = decoded.endLMS
            }
        }

        if (reader.offset != header.frameSize) { throw WWQOA.FrameDecodeError.trailingFrameDataMismatch }
        
        let interleaved = interleave(planarSamples)
        
        return .init(header: header, interleavedSamples: interleaved, planarSamples: planarSamples, startLMSStates: startLMSStates, endLMSStates: currentLMSStates, bytesRead: reader.offset)
    }
}

// MARK: - 小工具
private extension WWQOA.FrameDecoder {
    
    /// 讀取一個 frame 中所有聲道的 LMS states
    /// - Parameters:
    ///   - reader: 指向 LMS states 區塊起始位置的 `ByteReader`，讀取後 offset 會前進 `channels * 16` bytes
    ///   - channels: 聲道數，每個聲道對應一份 LMS state
    /// - Returns: 依聲道順序排列的 LMS states
    /// - Throws: 當資料不足、聲道數無效，或任一 LMS state 讀取失敗時拋出錯誤
    /// - Reference: QOA frame format 中，每個 channel 都包含一份 16-byte LMS state。[web:97]
    func readLMSStates(from reader: inout WWByteReader, channels: Int) throws -> [WWQOA.LMSState] {
        
        var states: [WWQOA.LMSState] = []
        states.reserveCapacity(channels)
        
        for _ in 0..<channels {
            let lms = try readLMSState(from: &reader)
            states.append(lms)
        }
        
        return states
    }
    
    /// 為 QOA frame 預先配置空的 planar samples 陣列
    /// - Parameters:
    ///   - channels: 聲道數
    ///   - samplesPerChannel: 每個聲道的樣本數
    /// - Returns: 已預分配容量的空 `planarSamples: [[Int16]]`
    func emptyPlanarSamples(channels: Int, samplesPerChannel: Int) -> [[Int16]] {
        
        var planarSamples = Array(repeating: Array<Int16>(), count: channels)
        
        for channel in 0..<channels {
            planarSamples[channel].reserveCapacity(samplesPerChannel)
        }
        
        return planarSamples
    }
}

// MARK: - 內部解析
private extension WWQOA.FrameDecoder {
    
    /// 讀取單一 QOA frame header
    ///
    /// QOA frame header 固定為 8 bytes，欄位配置如下：
    /// ┌──────────┬────────────┬──────────────────┬───────────┐
    /// │ 1 byte   │ 3 bytes    │ 2 bytes          │ 2 bytes   │
    /// │ channels │ sampleRate │ samplesPerChannel│ frameSize │
    /// └──────────┴────────────┴──────────────────┴───────────┘
    ///
    /// 各欄位皆以 Big Endian 儲存：
    /// - `channels`：聲道數
    /// - `sampleRate`：採樣率（24-bit unsigned integer）
    /// - `samplesPerChannel`：此 frame 每個聲道包含的 sample 數
    /// - `frameSize`：此 frame 總大小（bytes），包含 frame header 本身
    ///
    /// - Parameter reader: 用於讀取位元組資料的 `ByteReader`，讀取後 offset 會前進 8 bytes
    /// - Returns: 解碼後的 `WWQOA.FrameHeader`
    /// - Throws: 當剩餘資料不足 8 bytes 或欄位讀取失敗時拋出錯誤
    /// - Reference: QOA 規格中 `frame header` 定義，`frameSize` 包含 header 本身。[web:97]
    func readFrameHeader(from reader: inout WWByteReader) throws -> WWQOA.FrameHeader {
        
        let channels = Int(try reader.readUIntValue() as UInt8)
        let sampleRate = Int(try reader.readUInt24Value())
        let samplesPerChannel = Int(try reader.readUIntValue() as UInt16)
        let frameSize = Int(try reader.readUIntValue() as UInt16)
        
        return .init(channels: channels, sampleRate: sampleRate, samplesPerChannel: samplesPerChannel, frameSize: frameSize)
    }
    
    /// 根據 QOA frame header 計算預期 frame 大小（用於驗證）=> frameSize = 8 + (channels × 16) + (slicesPerChannel × channels × 8)
    ///
    /// QOA frame 結構：
    /// ┌───────────────────────┐
    /// │  8 bytes frame header │ ← `WWQOA.Constant.frameHeaderSize`
    /// ├───────────────────────┤
    /// │  channels × 16 bytes  │ ← LMS state（每個聲道 16 bytes）
    /// │  LMS state            │   權重與歷史狀態，解碼下一 frame 時需要
    /// ├───────────────────────┤
    /// │  slices × channels ×  │ ← 每個 slice 固定 8 bytes
    /// │     8 bytes slices    │   每個 slice 包含 20 個 samples 的壓縮資料
    /// └───────────────────────┘
    ///
    /// - Parameter header: QOA frame header
    /// - Returns: 完整 frame 預期大小（bytes）
    /// - Reference: [QOA Specification §4.2 Frame Format][web:97]
    func calculateExpectedFrameSize(with header: WWQOA.FrameHeader) -> Int {
        
        let slicesPerChannel = Int(ceil(Double(header.samplesPerChannel) / Double(WWQOA.Constant.sliceSamples)))
        let expectedFrameSize = WWQOA.Constant.frameHeaderSize + header.channels * WWQOA.Constant.lmsStateSizePerChannel + slicesPerChannel * header.channels * WWQOA.Constant.sliceSize
        
        return expectedFrameSize
    }
    
    /// 讀取單一聲道的 LMS state
    ///
    /// 在 QOA frame 中，每個聲道都會保存一份 LMS（Least Mean Squares）狀態，
    /// 用來作為該聲道後續 slice 解碼時的預測器初始值。
    ///
    /// LMS state 固定為 16 bytes，結構如下：
    /// - 4 × Int16 `history`
    /// - 4 × Int16 `weights`
    ///
    /// 總計：
    /// `4 * 2 bytes + 4 * 2 bytes = 16 bytes`
    ///
    /// 所有欄位皆以 Big Endian 讀取，並轉成 `Int32` 儲存在 `WWQOA.LMSState` 中，
    /// 以便後續做預測計算時避免中間乘加溢位。
    /// - Parameter reader: 指向 LMS state 起始位置的 `ByteReader`，讀取後 offset 會前進 16 bytes
    /// - Returns: 解碼後的 `WWQOA.LMSState`
    /// - Throws: 當剩餘資料不足 16 bytes 或讀取失敗時拋出錯誤
    /// - Reference: QOA frame format 中每個 channel 包含 16-byte LMS state。[web:97]
    func readLMSState(from reader: inout WWByteReader) throws -> WWQOA.LMSState {
        
        let capacitySize = WWQOA.LMS.deltaShift
        
        var history: [Int32] = []
        var weights: [Int32] = []
        
        history.reserveCapacity(capacitySize)
        weights.reserveCapacity(capacitySize)
        
        for _ in 0..<capacitySize {
            history.append(Int32(try reader.readIntValue() as Int16))
        }
        
        for _ in 0..<capacitySize {
            weights.append(Int32(try reader.readIntValue() as Int16))
        }
        
        return .init(history: history, weights: weights)
    }
    
    /// 將 planar（分聲道）PCM samples 轉換為 interleaved（交錯）格式
    ///
    /// PCM 音訊資料常見兩種儲存方式：
    /// 1. **Planar**：`[[L0,R0], [L1,R1], ...]` ← 每個聲道獨立陣列
    /// 2. **Interleaved**：`[L0,R0, L1,R1, ...]` ← 樣本交錯排列
    ///
    /// WAV、MP3、AAC 等檔案格式通常要求 **interleaved** 格式，
    /// 而 DSP 處理（FFT、filtering）通常用 **planar** 格式更方便。
    ///
    /// 轉換公式：`interleaved[i * channels + c] = planar[c][i]`
    ///
    /// - Parameter planar: 輸入的 planar PCM samples，`planar[c]` 是第 c 聲道的樣本
    /// - Returns: Interleaved PCM samples，`[ch0_s0, ch1_s0, ch2_s0, ..., ch0_s1, ch1_s1, ...]`
    /// - Note: 所有聲道必須長度相同，否則以第一聲道長度為準
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

//
//  AudioImporter.swift
//  Example
//
//  Created by iOS on 2026/4/20.
//

import AVFoundation
import WWQOA

enum AudioImporter {}

extension AudioImporter {

    enum Error: Swift.Error, LocalizedError {
        case unsupportedFormat
        case failedToCreateBuffer
        case failedToReadPCMData
        case invalidFrameLength

        var errorDescription: String? {
            switch self {
            case .unsupportedFormat:
                return "Unsupported audio format or failed to decode as PCM Int16."
            case .failedToCreateBuffer:
                return "Failed to create AVAudioPCMBuffer."
            case .failedToReadPCMData:
                return "Failed to read PCM sample data from AVAudioPCMBuffer."
            case .invalidFrameLength:
                return "Invalid frame length."
            }
        }
    }
}

extension AudioImporter {

    static func loadQOAInput(from url: URL) throws -> WWQOA.FileEncodeInput {
        try loadPCMInt16(from: url)
    }
}

extension AudioImporter {

    /// 讀取 Apple 可解碼的音訊檔，轉成 Int16 interleaved PCM
    static func loadPCMInt16(from url: URL) throws -> WWQOA.FileEncodeInput {
        let audioFile = try AVAudioFile(
            forReading: url,
            commonFormat: .pcmFormatInt16,
            interleaved: false
        )

        let processingFormat = audioFile.processingFormat
        let channelCount = Int(processingFormat.channelCount)
        let sampleRate = Int(processingFormat.sampleRate)
        let frameCount = AVAudioFrameCount(audioFile.length)

        guard frameCount > 0 else {
            throw Error.invalidFrameLength
        }

        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: processingFormat,
            frameCapacity: frameCount
        ) else {
            throw Error.failedToCreateBuffer
        }

        try audioFile.read(into: buffer)

        let samples = try extractInterleavedInt16Samples(from: buffer)

        return WWQOA.FileEncodeInput(
            interleavedSamples: samples,
            channels: channelCount,
            sampleRate: sampleRate
        )
    }
}

private extension AudioImporter {

    static func extractInterleavedInt16Samples(
        from buffer: AVAudioPCMBuffer
    ) throws -> [Int16] {
        let channelCount = Int(buffer.format.channelCount)
        let frameLength = Int(buffer.frameLength)

        guard frameLength >= 0 else {
            throw Error.invalidFrameLength
        }

        guard let channelData = buffer.int16ChannelData else {
            throw Error.failedToReadPCMData
        }

        if channelCount == 1 {
            let mono = UnsafeBufferPointer(
                start: channelData[0],
                count: frameLength
            )
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

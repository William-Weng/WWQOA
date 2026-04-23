//
//  Debug.swift
//  WWQOA
//
//  Created by William.Weng on 2026/04/20.
//

import Foundation

extension WWQOA.Debug {

    struct Metrics: CustomStringConvertible {
        let sampleCount: Int
        let mse: Double
        let rmse: Double
        let peakAbsoluteError: Int
        let snr: Double

        public var description: String {
            """
            sampleCount: \(sampleCount)
            MSE: \(mse)
            RMSE: \(rmse)
            PeakAbsError: \(peakAbsoluteError)
            SNR: \(snr.isFinite ? "\(snr) dB" : "inf")
            """
        }
    }

    struct SampleDiff: CustomStringConvertible {
        let index: Int
        let original: Int16
        let decoded: Int16
        let delta: Int

        public var description: String {
            String(
                format: "[%04d] original=%7d decoded=%7d delta=%7d",
                index, Int(original), Int(decoded), delta
            )
        }
    }

    struct FrameRoundtripReport: CustomStringConvertible {
        let metrics: Metrics
        let encodedFrameSize: Int
        let channels: Int
        let sampleRate: Int
        let samplesPerChannel: Int
        let sampleDiffs: [SampleDiff]

        public var description: String {
            var lines: [String] = []
            lines.append("=== WWQOA Frame Roundtrip Report ===")
            lines.append("channels: \(channels)")
            lines.append("sampleRate: \(sampleRate)")
            lines.append("samplesPerChannel: \(samplesPerChannel)")
            lines.append("encodedFrameSize: \(encodedFrameSize) bytes")
            lines.append(metrics.description)
            lines.append("--- sample diff preview ---")
            if sampleDiffs.isEmpty {
                lines.append("(no sample diff)")
            } else {
                lines.append(contentsOf: sampleDiffs.map(\.description))
            }
            return lines.joined(separator: "\n")
        }
    }

    struct FileRoundtripReport: CustomStringConvertible {
        let metrics: Metrics
        let encodedFileSize: Int
        let frameCount: Int
        let channels: Int
        let sampleRate: Int
        let samplesPerChannel: Int
        let sampleDiffs: [SampleDiff]

        public var description: String {
            var lines: [String] = []
            lines.append("=== WWQOA File Roundtrip Report ===")
            lines.append("channels: \(channels)")
            lines.append("sampleRate: \(sampleRate)")
            lines.append("samplesPerChannel: \(samplesPerChannel)")
            lines.append("frameCount: \(frameCount)")
            lines.append("encodedFileSize: \(encodedFileSize) bytes")
            lines.append(metrics.description)
            lines.append("--- sample diff preview ---")
            if sampleDiffs.isEmpty {
                lines.append("(no sample diff)")
            } else {
                lines.append(contentsOf: sampleDiffs.map(\.description))
            }
            return lines.joined(separator: "\n")
        }
    }
}

extension WWQOA.Debug {

    static func meanSquaredError(_ original: [Int16], _ decoded: [Int16]) -> Double {
        precondition(original.count == decoded.count)
        guard !original.isEmpty else { return 0 }

        let sum = zip(original, decoded).reduce(0.0) { partial, pair in
            let d = Double(Int(pair.0) - Int(pair.1))
            return partial + d * d
        }

        return sum / Double(original.count)
    }

    static func rootMeanSquaredError(_ original: [Int16], _ decoded: [Int16]) -> Double {
        sqrt(meanSquaredError(original, decoded))
    }

    static func peakAbsoluteError(_ original: [Int16], _ decoded: [Int16]) -> Int {
        precondition(original.count == decoded.count)
        return zip(original, decoded)
            .map { abs(Int($0) - Int($1)) }
            .max() ?? 0
    }

    static func signalToNoiseRatio(_ original: [Int16], _ decoded: [Int16]) -> Double {
        precondition(original.count == decoded.count)
        guard !original.isEmpty else { return .infinity }

        let signalPower = original.reduce(0.0) { partial, sample in
            let x = Double(Int(sample))
            return partial + x * x
        }

        let noisePower = zip(original, decoded).reduce(0.0) { partial, pair in
            let d = Double(Int(pair.0) - Int(pair.1))
            return partial + d * d
        }

        guard noisePower > 0 else { return .infinity }
        return 10.0 * log10(signalPower / noisePower)
    }

    static func metrics(original: [Int16], decoded: [Int16]) -> Metrics {
        let mse = meanSquaredError(original, decoded)
        return Metrics(
            sampleCount: original.count,
            mse: mse,
            rmse: sqrt(mse),
            peakAbsoluteError: peakAbsoluteError(original, decoded),
            snr: signalToNoiseRatio(original, decoded)
        )
    }

    static func sampleDiffs(
        original: [Int16],
        decoded: [Int16],
        limit: Int = 32
    ) -> [SampleDiff] {
        precondition(original.count == decoded.count)

        return zip(original, decoded)
            .enumerated()
            .prefix(limit)
            .map { index, pair in
                SampleDiff(
                    index: index,
                    original: pair.0,
                    decoded: pair.1,
                    delta: Int(pair.0) - Int(pair.1)
                )
            }
    }
}

extension WWQOA.Debug {

    static func roundtripFrame(
        interleavedSamples: [Int16],
        channels: Int,
        sampleRate: Int,
        diffPreviewCount: Int = 32
    ) throws -> FrameRoundtripReport {
        let input = WWQOA.FrameInput(
            interleavedSamples: interleavedSamples,
            channels: channels,
            sampleRate: sampleRate
        )

        let frameEncoder = WWQOA.FrameEncoder()

        let encoded = frameEncoder.encodeFrame(input)
        let decoded = try WWQOA.FrameDecoder().decodeFrame(encoded.data)

        let metrics = metrics(
            original: interleavedSamples,
            decoded: decoded.interleavedSamples
        )

        return FrameRoundtripReport(
            metrics: metrics,
            encodedFrameSize: encoded.data.count,
            channels: decoded.header.channels,
            sampleRate: decoded.header.sampleRate,
            samplesPerChannel: decoded.header.samplesPerChannel,
            sampleDiffs: sampleDiffs(
                original: interleavedSamples,
                decoded: decoded.interleavedSamples,
                limit: diffPreviewCount
            )
        )
    }
}

extension WWQOA.Debug {

    static func roundtripFile(
        interleavedSamples: [Int16],
        channels: Int,
        sampleRate: Int,
        diffPreviewCount: Int = 32
    ) throws -> FileRoundtripReport {
        let input = WWQOA.FileEncodeInput(
            interleavedSamples: interleavedSamples,
            channels: channels,
            sampleRate: sampleRate
        )

        let encoded = WWQOA.shared.encodeFile(input)
        let decoded = try WWQOA.shared.decodeFile(encoded.data)

        let metrics = metrics(
            original: interleavedSamples,
            decoded: decoded.interleavedSamples
        )

        return FileRoundtripReport(
            metrics: metrics,
            encodedFileSize: encoded.data.count,
            frameCount: encoded.frameCount,
            channels: decoded.channels,
            sampleRate: decoded.sampleRate,
            samplesPerChannel: decoded.planarSamples.first?.count ?? 0,
            sampleDiffs: sampleDiffs(
                original: interleavedSamples,
                decoded: decoded.interleavedSamples,
                limit: diffPreviewCount
            )
        )
    }
}

extension WWQOA.Debug {

    @discardableResult
    static func printFrameRoundtrip(
        interleavedSamples: [Int16],
        channels: Int,
        sampleRate: Int,
        diffPreviewCount: Int = 32
    ) throws -> FrameRoundtripReport {
        let report = try roundtripFrame(
            interleavedSamples: interleavedSamples,
            channels: channels,
            sampleRate: sampleRate,
            diffPreviewCount: diffPreviewCount
        )
        print(report.description)
        return report
    }

    @discardableResult
    static func printFileRoundtrip(
        interleavedSamples: [Int16],
        channels: Int,
        sampleRate: Int,
        diffPreviewCount: Int = 32
    ) throws -> FileRoundtripReport {
        let report = try roundtripFile(
            interleavedSamples: interleavedSamples,
            channels: channels,
            sampleRate: sampleRate,
            diffPreviewCount: diffPreviewCount
        )
        print(report.description)
        return report
    }
}

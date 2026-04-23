//
//  WWQOATestTone.swift
//  Example
//
//  Created by William.Weng on 2026/04/20.
//

import Foundation
import WWQOA

enum WWQOATestTone {}

extension WWQOATestTone {

    struct ADSR: Equatable {
        let attack: Double   // seconds
        let decay: Double    // seconds
        let sustain: Double  // 0...1
        let release: Double  // seconds

        init(
            attack: Double,
            decay: Double,
            sustain: Double,
            release: Double
        ) {
            self.attack = max(0, attack)
            self.decay = max(0, decay)
            self.sustain = min(max(sustain, 0), 1)
            self.release = max(0, release)
        }

        static let softPluck = ADSR(
            attack: 0.015,
            decay: 0.06,
            sustain: 0.78,
            release: 0.08
        )

        static let organLike = ADSR(
            attack: 0.01,
            decay: 0.02,
            sustain: 0.95,
            release: 0.03
        )
    }

    struct Vibrato: Equatable {
        let rate: Double   // Hz
        let depth: Double  // fractional, e.g. 0.003 = 0.3%

        init(rate: Double, depth: Double) {
            self.rate = max(0, rate)
            self.depth = max(0, depth)
        }

        static let gentle = Vibrato(rate: 5.5, depth: 0.0035)
        static let none = Vibrato(rate: 0, depth: 0)
    }

    struct ToneStyle: Equatable {
        let amplitude: Double
        let adsr: ADSR
        let vibrato: Vibrato?
        let harmonicMix: [Double]

        init(
            amplitude: Double = 12000.0,
            adsr: ADSR = .softPluck,
            vibrato: Vibrato? = nil,
            harmonicMix: [Double] = [1.0]
        ) {
            self.amplitude = max(0, amplitude)
            self.adsr = adsr
            self.vibrato = vibrato
            self.harmonicMix = harmonicMix.isEmpty ? [1.0] : harmonicMix
        }

        static let pureSine = ToneStyle(
            amplitude: 12000.0,
            adsr: .softPluck,
            vibrato: nil,
            harmonicMix: [1.0]
        )

        static let mellowLead = ToneStyle(
            amplitude: 10000.0,
            adsr: .softPluck,
            vibrato: .gentle,
            harmonicMix: [1.0, 0.18, 0.08]
        )
    }

    struct Note: Equatable {
        let frequency: Double
        let duration: Double

        init(frequency: Double, duration: Double) {
            self.frequency = max(0, frequency)
            self.duration = max(0, duration)
        }
    }
}

extension WWQOATestTone {

    enum Pitch {
        static let c4 = 261.63
        static let d4 = 293.66
        static let e4 = 329.63
        static let f4 = 349.23
        static let g4 = 392.00
        static let a4 = 440.00
        static let b4 = 493.88
        static let c5 = 523.25
    }
}

private extension WWQOATestTone {

    static func normalizedADSR(for duration: Double, adsr: ADSR) -> ADSR {
        let total = adsr.attack + adsr.decay + adsr.release
        guard total > duration, total > 0 else { return adsr }

        let scale = duration / total
        return ADSR(
            attack: adsr.attack * scale,
            decay: adsr.decay * scale,
            sustain: adsr.sustain,
            release: adsr.release * scale
        )
    }

    static func envelopeValue(
        at time: Double,
        noteDuration: Double,
        adsr: ADSR
    ) -> Double {
        let adsr = normalizedADSR(for: noteDuration, adsr: adsr)

        let a = adsr.attack
        let d = adsr.decay
        let s = adsr.sustain
        let r = adsr.release

        let sustainStart = a + d
        let releaseStart = max(sustainStart, noteDuration - r)

        if time < 0 || time >= noteDuration { return 0 }

        if a > 0 && time < a {
            return time / a
        }

        if d > 0 && time < sustainStart {
            let x = (time - a) / d
            return 1.0 + (s - 1.0) * x
        }

        if time < releaseStart {
            return s
        }

        if r > 0 && time < noteDuration {
            let x = (time - releaseStart) / r
            return s * (1.0 - x)
        }

        return 0
    }

    static func vibratoDepthAtTime(
        _ time: Double,
        baseDepth: Double,
        fadeInTime: Double = 0.12
    ) -> Double {
        guard fadeInTime > 0 else { return baseDepth }
        let x = min(max(time / fadeInTime, 0), 1)
        return baseDepth * x
    }

    static func clamp16(_ value: Double) -> Int16 {
        let rounded = Int(value.rounded())
        return Int16(max(-32768, min(32767, rounded)))
    }
}

extension WWQOATestTone {

    static func makeNote(
        frequency: Double,
        duration: Double,
        sampleRate: Int = 44_100,
        style: ToneStyle = .pureSine
    ) -> [Int16] {
        guard frequency > 0, duration > 0, sampleRate > 0 else { return [] }

        let count = Int(Double(sampleRate) * duration)
        let dt = 1.0 / Double(sampleRate)
        var phase = 0.0

        return (0..<count).map { i in
            let t = Double(i) * dt
            let env = envelopeValue(at: t, noteDuration: duration, adsr: style.adsr)

            let currentFrequency: Double
            if let vibrato = style.vibrato, vibrato.rate > 0, vibrato.depth > 0 {
                let lfo = sin(2.0 * .pi * vibrato.rate * t)
                let depth = vibratoDepthAtTime(t, baseDepth: vibrato.depth)
                currentFrequency = frequency * (1.0 + depth * lfo)
            } else {
                currentFrequency = frequency
            }

            phase += 2.0 * .pi * currentFrequency * dt

            var waveform = 0.0
            for (index, weight) in style.harmonicMix.enumerated() {
                let harmonic = Double(index + 1)
                waveform += weight * sin(phase * harmonic)
            }

            let sample = waveform * style.amplitude * env
            return clamp16(sample)
        }
    }
}

extension WWQOATestTone {

    static func makeMelody(
        _ notes: [Note],
        sampleRate: Int = 44_100,
        style: ToneStyle = .pureSine
    ) -> [Int16] {
        notes.flatMap {
            makeNote(
                frequency: $0.frequency,
                duration: $0.duration,
                sampleRate: sampleRate,
                style: style
            )
        }
    }
}

extension WWQOATestTone {

    static func doReMiReDo(
        sampleRate: Int = 44_100,
        style: ToneStyle = .mellowLead
    ) -> [Int16] {
        let d = 0.4

        let notes: [Note] = [
            Note(frequency: Pitch.c4, duration: d),
            Note(frequency: Pitch.d4, duration: d),
            Note(frequency: Pitch.e4, duration: d),
            Note(frequency: Pitch.d4, duration: d),
            Note(frequency: Pitch.c4, duration: d)
        ]

        return makeMelody(notes, sampleRate: sampleRate, style: style)
    }
}

extension WWQOATestTone {

    static func testA440(
        sampleRate: Int = 44_100,
        duration: Double = 1.0,
        style: ToneStyle = .pureSine
    ) -> [Int16] {
        makeNote(
            frequency: Pitch.a4,
            duration: duration,
            sampleRate: sampleRate,
            style: style
        )
    }
}

extension WWQOATestTone {

    static func stereoTest(
        sampleRate: Int = 44_100,
        duration: Double = 1.0
    ) -> [Int16] {
        let left = makeNote(
            frequency: Pitch.a4,
            duration: duration,
            sampleRate: sampleRate,
            style: .pureSine
        )

        let right = makeNote(
            frequency: Pitch.e4,
            duration: duration,
            sampleRate: sampleRate,
            style: .mellowLead
        )

        let count = min(left.count, right.count)
        var interleaved: [Int16] = []
        interleaved.reserveCapacity(count * 2)

        for i in 0..<count {
            interleaved.append(left[i])
            interleaved.append(right[i])
        }

        return interleaved
    }
}

extension WWQOATestTone {

    static func makeDoReMiReDoQOAInput(
        sampleRate: Int = 44_100,
        style: ToneStyle = .mellowLead
    ) -> WWQOA.FileEncodeInput {
        let pcm = doReMiReDo(sampleRate: sampleRate, style: style)
        return WWQOA.FileEncodeInput(
            interleavedSamples: pcm,
            channels: 1,
            sampleRate: sampleRate
        )
    }
}

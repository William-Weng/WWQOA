//
//  ViewController.swift
//  Example
//
//  Created by William.Weng on 2026/04/20.
//

import UIKit
import WWQOA

final class ViewController: UIViewController {
    
    override func viewDidLoad() {
        
        super.viewDidLoad()

        do {
            let qoaUrl = try encoding()
            _ = try decoding(qoaUrl: qoaUrl)
        } catch {
            print("QOA file roundtrip failed:", error)
        }
    }
}

private extension ViewController {
    
    func encoding() throws -> URL {
        
        let m4aUrl = Bundle.main.url(forResource: "do-re-mi-re-do", withExtension: "m4a")!
        let pcmInput = try WWQOA.shared.loadPCMInt16(from: m4aUrl)
        let qoaUrl = FileManager.default.temporaryDirectory.appendingPathComponent("do-re-mi-re-do.qoa")
        let result = try WWQOA.shared.encodeFile(pcmInput, to: qoaUrl)
        
        print("QOA File:", qoaUrl.path)
        print("PCM Size: \(pcmInput.interleavedSamples.count)")
        print("QOA Size:", result.count)
        print("Result:", result)
        
        return qoaUrl
    }
    
    func decoding(qoaUrl: URL, filename: String = "do-re-mi-re-do.wav") throws -> URL {
        
        let qoaData = try Data(contentsOf: qoaUrl)
        let wavUrl = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        let result = try WWQOA.shared.decodeFile(qoaData, to: wavUrl)
        
        print("\n----- decodingData -----")
        print("QOA Size: \(qoaData.count)")
        print("WAV File:", wavUrl.path)
        print("Result:", result)
        
        return wavUrl
    }
}

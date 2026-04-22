# [WWQOA](https://swiftpackageindex.com/William-Weng)
[![Swift-5.7](https://img.shields.io/badge/Swift-5.7-orange.svg?style=flat)](https://developer.apple.com/swift/) [![iOS-15.0](https://img.shields.io/badge/iOS-15.0-pink.svg?style=flat)](https://developer.apple.com/swift/) ![TAG](https://img.shields.io/github/v/tag/William-Weng/WWQOA) [![Swift Package Manager-SUCCESS](https://img.shields.io/badge/Swift_Package_Manager-SUCCESS-blue.svg?style=flat)](https://developer.apple.com/swift/) [![LICENSE](https://img.shields.io/badge/LICENSE-MIT-yellow.svg?style=flat)](https://developer.apple.com/swift/)

## 🎉 [相關說明](https://qoaformat.org/qoa-specification.pdf)
- [A Pure Swift implementation of the Quite OK Audio (QOA) codec, prioritizing simplicity, clarity, and zero dependencies. Well-suited for learning codec internals and integrating into Swift-based audio pipelines.](https://qoaformat.org/)
- [以 Pure Swift 實作的 Quite OK Audio（QOA）音訊編解碼器。強調簡潔、可讀性與零外部依賴，適合學習與實務整合。](https://github.com/phoboslab/qoa)

## 📷 [效果預覽](https://peterpanswift.github.io/iphone-bezels/)

![](https://github.com/user-attachments/assets/f311c5ae-6cf0-4695-93a7-a4c1ec873452)

<div align="center">

**⭐ 覺得好用就給個 Star 吧！**

</div>

## 💿 [安裝方式](https://medium.com/彼得潘的-swift-ios-app-開發問題解答集/使用-spm-安裝第三方套件-xcode-11-新功能-2c4ffcf85b4b)

使用 **Swift Package Manager (SPM)**：

```swift
dependencies: [
    .package(url: "https://github.com/William-Weng/WWQOA", .upToNextMinor(from: "1.0.0"))
]
```

## ✨ 功能特色
- ✅ 純 Swift 實作（無 C / 無 FFmpeg）
- ✅ 支援 interleaved PCM 輸入
- ✅ PCM → QOA 編碼
- ✅ QOA → PCM 解碼
- ✅ 支援輸出 WAV 檔案
- ✅ 完全支援 Swift Package Manager
    
## 🍄 [壓縮率](https://qoaformat.org/samples/)
| 格式 | 檔案大小 | 比例 |
| --- | --- | --- |
| `WAV (PCM16)` | 100%|1.0x|
| `QOA` | 約 35% – 45% | 約 2.2x – 2.8x|

## 🧲 內部參數

| 參數名稱 | 說明 |
|-----------|------|
| `encodeFile(_:)` | 取得QOA編碼完成的結果。 |
| `encodeFile(_:to:)` | 將編碼完成的QOA檔存成檔案。 |
| `decodeFile(_:)` | 解碼完整的 QOA 檔案為 `FileDecodeResult`。 |
| `decodeFile(_:to:)` | 解碼 QOA 檔案並直接匯出為 WAV 檔案。 |


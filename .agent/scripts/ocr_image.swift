import Foundation
import ImageIO
import Vision

// macOS Vision OCR: reads text out of image files and prints it to stdout.
// Usage: swift ocr_image.swift <image1> [image2 ...]

let arguments = CommandLine.arguments
guard arguments.count > 1 else {
    FileHandle.standardError.write("usage: swift ocr_image.swift <image path>\n".data(using: .utf8)!)
    exit(2)
}

for path in arguments.dropFirst() {
    let url = URL(fileURLWithPath: path)
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
        FileHandle.standardError.write("cannot load image: \(path)\n".data(using: .utf8)!)
        continue
    }
    let request = VNRecognizeTextRequest { request, _ in
        guard let observations = request.results as? [VNRecognizedTextObservation] else {
            return
        }
        let lines = observations.compactMap { $0.topCandidates(1).first?.string }
        print(lines.joined(separator: "\n"))
    }
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = true
    request.recognitionLanguages = ["zh-Hans", "en-US"]
    let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
    do {
        try handler.perform([request])
    } catch {
        FileHandle.standardError.write("OCR failed: \(error)\n".data(using: .utf8)!)
    }
}

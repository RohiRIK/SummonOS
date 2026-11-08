// Reads only an explicitly captured app window on an isolated GUI runner.
import AppKit
import Vision

let arguments = CommandLine.arguments
precondition(arguments.count == 2)
let image = URL(fileURLWithPath: arguments[1])
let request = VNRecognizeTextRequest()
request.recognitionLevel = .accurate
request.usesLanguageCorrection = false
try VNImageRequestHandler(url: image).perform([request])
for observation in request.results ?? [] {
    if let candidate = observation.topCandidates(1).first {
        print(candidate.string)
    }
}

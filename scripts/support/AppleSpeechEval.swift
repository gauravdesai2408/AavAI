import Foundation
import Speech

// Speech callbacks may arrive on the main queue. Keep it serviced while waiting.
func waitForCallback(_ semaphore: DispatchSemaphore) -> Bool {
    let deadline = Date().addingTimeInterval(60)
    while Date() < deadline {
        if semaphore.wait(timeout: .now()) == .success { return true }
        RunLoop.current.run(until: Date().addingTimeInterval(0.02))
    }
    return false
}

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("usage: AppleSpeechEval audio-file\n".utf8))
    exit(64)
}

let authorization = DispatchSemaphore(value: 0)
var authorizationStatus = SFSpeechRecognizer.authorizationStatus()
if authorizationStatus == .notDetermined {
    SFSpeechRecognizer.requestAuthorization { status in
        authorizationStatus = status
        authorization.signal()
    }
    guard waitForCallback(authorization) else {
        FileHandle.standardError.write(Data("authorization timed out\n".utf8))
        exit(69)
    }
}
guard authorizationStatus == .authorized else {
    FileHandle.standardError.write(Data("speech recognition not authorized: \(authorizationStatus.rawValue)\n".utf8))
    exit(77)
}

guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US")), recognizer.isAvailable else {
    FileHandle.standardError.write(Data("English speech recognizer unavailable\n".utf8))
    exit(69)
}

let request = SFSpeechURLRecognitionRequest(url: URL(fileURLWithPath: CommandLine.arguments[1]))
request.shouldReportPartialResults = false
guard recognizer.supportsOnDeviceRecognition else {
    FileHandle.standardError.write(Data("on-device recognition unavailable; no audio submitted\n".utf8))
    exit(69)
}
request.requiresOnDeviceRecognition = true

let finished = DispatchSemaphore(value: 0)
var transcript: String?
var recognitionError: Error?
let task = recognizer.recognitionTask(with: request) { result, error in
    if let result, result.isFinal {
        transcript = result.bestTranscription.formattedString
        finished.signal()
    } else if let error {
        recognitionError = error
        finished.signal()
    }
}

guard waitForCallback(finished) else {
    task.cancel()
    FileHandle.standardError.write(Data("recognition timed out\n".utf8))
    exit(69)
}
if let recognitionError {
    FileHandle.standardError.write(Data("recognition failed: \(recognitionError.localizedDescription)\n".utf8))
    exit(70)
}
FileHandle.standardOutput.write(Data(((transcript ?? "") + "\n").utf8))

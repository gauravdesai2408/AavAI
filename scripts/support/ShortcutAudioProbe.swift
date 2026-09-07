import CoreGraphics
import Foundation

let arguments = Array(CommandLine.arguments.dropFirst())
let isFocusChangeProbe = arguments.count == 2 && arguments[0] == "--focus-change"
guard arguments.count == 1 || isFocusChangeProbe else {
    FileHandle.standardError.write(Data("usage: ShortcutAudioProbe <audio-file>|--cancel|--focus-change <audio-file>\n".utf8))
    exit(64)
}

let argument = isFocusChangeProbe ? arguments[1] : arguments[0]
let isCancellationProbe = argument == "--cancel"
guard isCancellationProbe || FileManager.default.fileExists(atPath: argument) else {
    let audioPath = argument
    FileHandle.standardError.write(Data("audio file does not exist: \(audioPath)\n".utf8))
    exit(66)
}

guard let source = CGEventSource(stateID: .hidSystemState),
      let shortcutDown = CGEvent(keyboardEventSource: source, virtualKey: 49, keyDown: true),
      let shortcutUp = CGEvent(keyboardEventSource: source, virtualKey: 49, keyDown: false) else {
    FileHandle.standardError.write(Data("could not create keyboard events\n".utf8))
    exit(70)
}

shortcutDown.flags = .maskControl
shortcutUp.flags = .maskControl
shortcutDown.post(tap: .cghidEventTap)
Thread.sleep(forTimeInterval: 0.6)

if isCancellationProbe {
    guard let escapeDown = CGEvent(keyboardEventSource: source, virtualKey: 53, keyDown: true),
          let escapeUp = CGEvent(keyboardEventSource: source, virtualKey: 53, keyDown: false) else {
        exit(70)
    }
    escapeDown.post(tap: .cghidEventTap)
    escapeUp.post(tap: .cghidEventTap)
    shortcutUp.post(tap: .cghidEventTap)
    Thread.sleep(forTimeInterval: 0.2)
    exit(0)
}

let player = Process()
player.executableURL = URL(fileURLWithPath: "/usr/bin/afplay")
player.arguments = [argument]
try player.run()
if isFocusChangeProbe {
    Thread.sleep(forTimeInterval: 1.0)
    let focusChanger = Process()
    focusChanger.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    focusChanger.arguments = ["-a", "Finder"]
    try focusChanger.run()
    focusChanger.waitUntilExit()
}
player.waitUntilExit()
Thread.sleep(forTimeInterval: 0.4)

shortcutUp.post(tap: .cghidEventTap)
Thread.sleep(forTimeInterval: 0.2)

guard player.terminationStatus == 0 else { exit(player.terminationStatus) }

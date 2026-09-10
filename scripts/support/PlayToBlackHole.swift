import AppKit
import CoreAudio
import Foundation

// Evaluation-only playback: never changes system default audio devices.
var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
var size: UInt32 = 0
guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr else { fatalError("Cannot enumerate devices") }
var devices = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &devices) == noErr else { fatalError("Cannot read devices") }
func property(_ device: AudioDeviceID, _ selector: AudioObjectPropertySelector) -> String? {
    var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    var value: CFString = "" as CFString
    var size = UInt32(MemoryLayout<CFString>.size)
    guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr else { return nil }
    return value as String
}
guard let device = devices.first(where: { property($0, kAudioObjectPropertyName) == "BlackHole 2ch" }),
      let uid = property(device, kAudioDevicePropertyDeviceUID) else { fatalError("BlackHole 2ch unavailable") }
guard CommandLine.arguments.count == 2, let sound = NSSound(contentsOfFile: CommandLine.arguments[1], byReference: true) else { fatalError("Provide an audio file") }
sound.playbackDeviceIdentifier = uid
guard sound.play() else { fatalError("Playback failed") }
let deadline = Date().addingTimeInterval(sound.duration + 5)
while sound.isPlaying && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.05)) }
guard !sound.isPlaying else { sound.stop(); fatalError("Playback timed out") }
print("Played to BlackHole only: \(sound.duration) seconds")

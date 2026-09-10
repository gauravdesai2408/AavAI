import AppKit
import SwiftUI

struct TranscriptDetailView: View {
    let entry: TranscriptEntry
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Transcript").font(.title.bold())
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            Text(entry.createdAt.formatted()).foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(entry.cleanedText).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                    Divider()
                    Text("Original transcription").font(.headline)
                    Text(entry.rawText).textSelection(.enabled).foregroundStyle(.secondary)
                }
            }
            Button("Copy transcript") { copyTranscript(entry.cleanedText) }
        }.padding(24).frame(width: 620, height: 480)
    }
}

struct DictationDialogView: View {
    @EnvironmentObject private var coordinator: DictationCoordinator
    @Environment(\.dismiss) private var dismiss

    private var busy: Bool {
        if coordinator.isStarting && coordinator.state != .cancelled { return true }
        switch coordinator.state {
        case .listening, .finalizing, .cleaning, .inserting: return true
        default: return false
        }
    }

    private var status: String {
        switch coordinator.state {
        case .listening: "Listening — speak naturally, then stop to see your words."
        case .finalizing: "Transcribing your recording…"
        case .cleaning: "Polishing your words…"
        case .completed: "Your transcript is ready."
        case .failed(let error, _): error.message
        case .cancelled: "Recording cancelled."
        default: "Preparing microphone…"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Label("Your dictation", systemImage: "waveform").font(.title.bold())
                Spacer()
                if !busy { Button("Done") { dismiss() } }
            }
            Text(status).foregroundStyle(.secondary).accessibilityIdentifier("dictationStatus")
            if busy { ProgressView().controlSize(.small) }
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if !coordinator.polishedTranscript.isEmpty {
                        Text(coordinator.polishedTranscript).textSelection(.enabled)
                        Divider()
                        Text("Original transcription").font(.headline)
                    }
                    if !coordinator.rawTranscript.isEmpty {
                        Text(coordinator.rawTranscript).textSelection(.enabled)
                    } else {
                        Text("Your transcript will appear here after you stop recording.")
                            .foregroundStyle(.secondary)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                if coordinator.state == .listening {
                    Button("Stop and transcribe") { Task { await coordinator.finish() } }
                        .buttonStyle(.borderedProminent)
                }
                if busy {
                    Button("Cancel") { Task { await coordinator.cancel() } }
                } else {
                    Button("Record again") { Task { await coordinator.start(previewOnly: true) } }
                }
                Spacer()
                if !coordinator.polishedTranscript.isEmpty {
                    Button("Copy transcript") { copyTranscript(coordinator.polishedTranscript) }
                } else if !coordinator.rawTranscript.isEmpty {
                    Button("Copy original") { copyTranscript(coordinator.rawTranscript) }
                }
            }
        }.padding(24).frame(width: 620, height: 440)
            .interactiveDismissDisabled(busy)
    }
}

@MainActor private func copyTranscript(_ text: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
}

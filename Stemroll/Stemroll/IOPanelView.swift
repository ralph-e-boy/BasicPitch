import SwiftUI
import BasicPitch
struct IOPanelView: View {
    @Environment(TranscriptionViewModel.self) var vm

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            GroupBox("Audio Input") {
                HStack {
                    Text(vm.audioURL?.lastPathComponent ?? "No file selected")
                        .foregroundStyle(vm.audioURL == nil ? .secondary : .primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button("Choose…") { vm.selectAudioFile() }
                }
                .padding(4)
            }

            GroupBox("MIDI Output") {
                HStack {
                    Text(vm.effectiveOutputURL?.path ?? "—")
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .font(.caption)
                    Spacer()
                    Button("Override…") { vm.selectOutputFile() }
                        .disabled(vm.audioURL == nil)
                }
                .padding(4)
            }

            Divider()

            Button {
                vm.transcribe()
            } label: {
                Label("Transcribe", systemImage: "waveform.and.mic")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(vm.audioURL == nil || vm.isRunning)

            ResultView()

            Spacer()
        }
        .padding()
    }
}

private struct ResultView: View {
    @Environment(TranscriptionViewModel.self) var vm

    var body: some View {
        switch vm.state {
        case .idle:
            EmptyView()

        case .running(let done, let total):
            VStack(alignment: .leading, spacing: 8) {
                if total > 0 {
                    ProgressView(value: Double(done), total: Double(total))
                    Text("Window \(done) of \(total)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ProgressView()
                    Text("Starting…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

        case .success(let result):
            VStack(alignment: .leading, spacing: 6) {
                Label("Done", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.headline)
                Text("\(result.noteEvents.count) notes detected")
                if let first = result.noteEvents.min(by: { $0.startTime < $1.startTime }),
                   let last = result.noteEvents.max(by: { $0.endTime < $1.endTime }) {
                    Text(String(format: "%.2fs – %.2fs", first.startTime, last.endTime))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    let pitches = result.noteEvents.map(\.midiPitch)
                    if let lo = pitches.min(), let hi = pitches.max() {
                        Text("MIDI \(lo) – \(hi)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                HStack(spacing: 8) {
                    Button {
                        vm.revealInFinder()
                    } label: {
                        Label("Reveal in Finder", systemImage: "folder")
                    }

                    Button {
                        vm.isPlaying ? vm.stopMIDI() : vm.playMIDI()
                    } label: {
                        Label(vm.isPlaying ? "Stop" : "Play MIDI", systemImage: vm.isPlaying ? "stop.fill" : "play.fill")
                    }
                }
                .padding(.top, 4)
            }
            .padding()
            .background(.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))

        case .failure(let error):
            VStack(alignment: .leading, spacing: 4) {
                Label("Failed", systemImage: "xmark.circle.fill")
                    .foregroundStyle(.red)
                    .font(.headline)
                Text(error.localizedDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        }
    }
}

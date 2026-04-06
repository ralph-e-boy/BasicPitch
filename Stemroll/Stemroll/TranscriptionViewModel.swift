import Observation
import BasicPitch
import AVFoundation
import AppKit
import Foundation

enum TranscriptionState {
    case idle
    case running(completed: Int, total: Int)
    case success(BasicPitchResult)
    case failure(Error)
}

@Observable
final class TranscriptionViewModel {
    var audioURL: URL? = nil
    var outputURL: URL? = nil

    var state: TranscriptionState = .idle

    var effectiveOutputURL: URL? {
        outputURL ?? audioURL.map { $0.deletingPathExtension().appendingPathExtension("mid") }
    }

    var isRunning: Bool {
        if case .running = state { true } else { false }
    }

    var isPlaying: Bool = false

    var onsetThreshold: Double { didSet { UserDefaults.standard.set(onsetThreshold, forKey: "bp.onsetThreshold") } }
    var frameThreshold: Double { didSet { UserDefaults.standard.set(frameThreshold, forKey: "bp.frameThreshold") } }
    var minimumNoteLengthMS: Double { didSet { UserDefaults.standard.set(minimumNoteLengthMS, forKey: "bp.minimumNoteLengthMS") } }
    var midiTempo: Double { didSet { UserDefaults.standard.set(midiTempo, forKey: "bp.midiTempo") } }
    var includePitchBends: Bool { didSet { UserDefaults.standard.set(includePitchBends, forKey: "bp.includePitchBends") } }
    var multiplePitchBends: Bool { didSet { UserDefaults.standard.set(multiplePitchBends, forKey: "bp.multiplePitchBends") } }
    var melodiaTrick: Bool { didSet { UserDefaults.standard.set(melodiaTrick, forKey: "bp.melodiaTrick") } }
    var minimumFrequencyEnabled: Bool { didSet { UserDefaults.standard.set(minimumFrequencyEnabled, forKey: "bp.minimumFrequencyEnabled") } }
    var minimumFrequencyValue: Double { didSet { UserDefaults.standard.set(minimumFrequencyValue, forKey: "bp.minimumFrequencyValue") } }
    var maximumFrequencyEnabled: Bool { didSet { UserDefaults.standard.set(maximumFrequencyEnabled, forKey: "bp.maximumFrequencyEnabled") } }
    var maximumFrequencyValue: Double { didSet { UserDefaults.standard.set(maximumFrequencyValue, forKey: "bp.maximumFrequencyValue") } }

    private var transcriptionTask: Task<Void, Never>? = nil
    private var midiPlayer: AVMIDIPlayer? = nil

    init() {
        let defaults = UserDefaults.standard
        onsetThreshold = defaults.double(forKey: "bp.onsetThreshold").nonzero ?? 0.4
        frameThreshold = defaults.double(forKey: "bp.frameThreshold").nonzero ?? 0.25
        minimumNoteLengthMS = defaults.double(forKey: "bp.minimumNoteLengthMS").nonzero ?? 127.7
        midiTempo = defaults.double(forKey: "bp.midiTempo").nonzero ?? 120.0
        minimumFrequencyValue = defaults.double(forKey: "bp.minimumFrequencyValue").nonzero ?? 20.0
        maximumFrequencyValue = defaults.double(forKey: "bp.maximumFrequencyValue").nonzero ?? 4000.0

        includePitchBends = defaults.object(forKey: "bp.includePitchBends") as? Bool ?? true
        multiplePitchBends = defaults.object(forKey: "bp.multiplePitchBends") as? Bool ?? false
        melodiaTrick = defaults.object(forKey: "bp.melodiaTrick") as? Bool ?? true
        minimumFrequencyEnabled = defaults.object(forKey: "bp.minimumFrequencyEnabled") as? Bool ?? false
        maximumFrequencyEnabled = defaults.object(forKey: "bp.maximumFrequencyEnabled") as? Bool ?? false
    }

    func transcribe() {
        guard let audioURL, let outputURL = effectiveOutputURL else { return }
        transcriptionTask?.cancel()
        transcriptionTask = Task {
            state = .running(completed: 0, total: 0)
            do {
                let bp = try BasicPitch()
                var options = BasicPitchOptions()
                options.onsetThreshold = Float(onsetThreshold)
                options.frameThreshold = Float(frameThreshold)
                options.minimumNoteLengthMS = Float(minimumNoteLengthMS)
                options.minimumFrequency = minimumFrequencyEnabled ? Float(minimumFrequencyValue) : nil
                options.maximumFrequency = maximumFrequencyEnabled ? Float(maximumFrequencyValue) : nil
                options.includePitchBends = includePitchBends
                options.multiplePitchBends = multiplePitchBends
                options.melodiaTrick = melodiaTrick
                options.midiTempo = Float(midiTempo)
                options.progressHandler = { [weak self] done, total in
                    Task { @MainActor in
                        self?.state = .running(completed: done, total: total)
                    }
                }
                let result = try await bp.predict(audioURL: audioURL, options: options)
                try result.writeMIDI(to: outputURL)
                state = .success(result)
            } catch {
                state = .failure(error)
            }
        }
    }

    func selectAudioFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK {
            audioURL = panel.url
            outputURL = nil
            state = .idle
            isPlaying = false
            midiPlayer?.stop()
            midiPlayer = nil
        }
    }

    func selectOutputFile() {
        guard let audioURL else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.midi]
        panel.nameFieldStringValue = defaultMIDIURL(for: audioURL).lastPathComponent
        panel.directoryURL = audioURL.deletingLastPathComponent()
        if panel.runModal() == .OK {
            outputURL = panel.url
        }
    }

    func revealInFinder() {
        guard let url = effectiveOutputURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func playMIDI() {
        guard let url = effectiveOutputURL else { return }
        midiPlayer = try? AVMIDIPlayer(contentsOf: url, soundBankURL: nil)
        midiPlayer?.prepareToPlay()
        isPlaying = true
        midiPlayer?.play { [weak self] in
            Task { @MainActor in
                self?.isPlaying = false
            }
        }
    }

    func stopMIDI() {
        midiPlayer?.stop()
        isPlaying = false
    }

    private func defaultMIDIURL(for audioURL: URL) -> URL {
        audioURL.deletingPathExtension().appendingPathExtension("mid")
    }
}

private extension Double {
    var nonzero: Double? { self != 0 ? self : nil }
}

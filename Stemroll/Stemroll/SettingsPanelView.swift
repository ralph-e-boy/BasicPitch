import SwiftUI

struct SettingsPanelView: View {
    @Environment(TranscriptionViewModel.self) var vm

    var body: some View {
        @Bindable var vm = vm

        ScrollView {
            Form {
                Section("Detection") {
                    VStack(alignment: .leading) {
                        HStack {
                            Text("Onset threshold")
                            Spacer()
                            Text(vm.onsetThreshold, format: .number.precision(.fractionLength(2)))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: $vm.onsetThreshold, in: 0...1, step: 0.01)
                    }

                    VStack(alignment: .leading) {
                        HStack {
                            Text("Frame threshold")
                            Spacer()
                            Text(vm.frameThreshold, format: .number.precision(.fractionLength(2)))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: $vm.frameThreshold, in: 0...1, step: 0.01)
                    }

                    HStack {
                        Text("Min note length")
                        Spacer()
                        TextField("ms", value: $vm.minimumNoteLengthMS,
                                  format: .number.precision(.fractionLength(1)))
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                        Stepper("", value: $vm.minimumNoteLengthMS, in: 0...1000, step: 10)
                            .labelsHidden()
                        Text("ms").foregroundStyle(.secondary)
                    }

                    Toggle("Melodia trick", isOn: $vm.melodiaTrick)
                }

                Section("Frequency Range") {
                    HStack {
                        Toggle("Min frequency", isOn: $vm.minimumFrequencyEnabled)
                        Spacer()
                        TextField("Hz", value: $vm.minimumFrequencyValue,
                                  format: .number.precision(.fractionLength(0)))
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                            .disabled(!vm.minimumFrequencyEnabled)
                        Text("Hz").foregroundStyle(.secondary)
                    }

                    HStack {
                        Toggle("Max frequency", isOn: $vm.maximumFrequencyEnabled)
                        Spacer()
                        TextField("Hz", value: $vm.maximumFrequencyValue,
                                  format: .number.precision(.fractionLength(0)))
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                            .disabled(!vm.maximumFrequencyEnabled)
                        Text("Hz").foregroundStyle(.secondary)
                    }
                }

                Section("Pitch Bends") {
                    Toggle("Include pitch bends", isOn: $vm.includePitchBends)
                    Toggle("Multiple pitch bends (multi-track MIDI)", isOn: $vm.multiplePitchBends)
                        .disabled(!vm.includePitchBends)
                }

                Section("MIDI") {
                    HStack {
                        Text("Tempo")
                        Spacer()
                        TextField("BPM", value: $vm.midiTempo,
                                  format: .number.precision(.fractionLength(1)))
                            .multilineTextAlignment(.trailing)
                            .frame(width: 70)
                        Stepper("", value: $vm.midiTempo, in: 20...300, step: 1)
                            .labelsHidden()
                        Text("BPM").foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)
            .padding()
        }
    }
}

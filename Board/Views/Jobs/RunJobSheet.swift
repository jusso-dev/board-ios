import SwiftUI

struct RunJobSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    let issue: Int
    let onStarted: (JobRecord) -> Void

    @State private var harness: Harness = .codex
    @State private var crew: [Harness] = []
    @State private var prompt = ""
    @State private var isStarting = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Primary harness") {
                    Picker("Harness", selection: $harness) {
                        ForEach(allowedHarnesses) { value in
                            Label(value.title, systemImage: value.systemImage)
                                .tag(value)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityLabel("Primary harness")
                    .accessibilityIdentifier("harness-picker")
                }

                Section {
                    if crew.isEmpty {
                        Text("No crew. The primary harness runs by itself.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(crew.enumerated()), id: \.offset) { index, value in
                            HStack {
                                Text(index + 1, format: .number)
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                    .frame(width: 20)
                                Label(value.title, systemImage: value.systemImage)
                                Spacer()
                                Button {
                                    moveCrew(at: index, offset: -1)
                                } label: {
                                    Image(systemName: "arrow.up")
                                }
                                .disabled(index == 0)
                                .accessibilityLabel("Move \(value.title) earlier")
                                Button {
                                    moveCrew(at: index, offset: 1)
                                } label: {
                                    Image(systemName: "arrow.down")
                                }
                                .disabled(index == crew.count - 1)
                                .accessibilityLabel("Move \(value.title) later")
                                Button(role: .destructive) {
                                    crew.remove(at: index)
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .accessibilityLabel("Remove \(value.title) from crew")
                            }
                        }
                    }

                    Menu {
                        ForEach(allowedHarnesses) { value in
                            Button {
                                crew.append(value)
                            } label: {
                                Label(value.title, systemImage: value.systemImage)
                            }
                        }
                    } label: {
                        Label("Add crew member", systemImage: "plus")
                    }
                    .disabled(crew.count >= 5)
                    .accessibilityIdentifier("add-crew-button")
                } header: {
                    Text("Sequential crew")
                } footer: {
                    Text("Crew members run in this order after the primary harness. The API allows up to five.")
                }

                Section("Extra prompt") {
                    TextEditor(text: $prompt)
                        .frame(minHeight: 140)
                        .accessibilityLabel("Optional job prompt")
                        .accessibilityIdentifier("job-prompt")
                        .onChange(of: prompt) { _, newValue in
                            if newValue.count > 32_768 {
                                prompt = String(newValue.prefix(32_768))
                            }
                        }
                }

                Section {
                    Text("The phone starts the job. All coding tools run on the board guest.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Run issue #\(issue)")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                if !allowedHarnesses.contains(harness), let first = allowedHarnesses.first {
                    harness = first
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isStarting ? "Starting" : "Start") {
                        Task { await start() }
                    }
                    .disabled(isStarting || allowedHarnesses.isEmpty)
                    .accessibilityLabel("Start job")
                    .accessibilityIdentifier("start-job-button")
                }
            }
        }
    }

    private var allowedHarnesses: [Harness] {
        let values = model.server?.harnesses ?? Harness.allCases
        return values.isEmpty ? Harness.allCases : values
    }

    private func moveCrew(at index: Int, offset: Int) {
        let destination = index + offset
        guard crew.indices.contains(index), crew.indices.contains(destination) else { return }
        crew.swapAt(index, destination)
    }

    private func start() async {
        isStarting = true
        defer { isStarting = false }
        guard let job = await model.startJob(issue: issue, harness: harness, prompt: prompt, crew: crew) else {
            return
        }
        onStarted(job)
        dismiss()
    }
}

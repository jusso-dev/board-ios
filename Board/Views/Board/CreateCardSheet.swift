import SwiftUI

struct CreateCardSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var bodyText = ""
    @State private var column: BoardColumn
    @State private var isSaving = false

    init(initialColumn: BoardColumn) {
        _column = State(initialValue: initialColumn)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Card") {
                    TextField("Title", text: $title, axis: .vertical)
                        .lineLimit(1...3)
                        .accessibilityIdentifier("new-card-title")
                        .onChange(of: title) { _, newValue in
                            if newValue.count > 256 {
                                title = String(newValue.prefix(256))
                            }
                        }

                    TextField("Body", text: $bodyText, axis: .vertical)
                        .lineLimit(5...12)
                        .accessibilityIdentifier("new-card-body")
                }

                Section("Column") {
                    Picker("Column", selection: $column) {
                        ForEach(BoardColumn.allCases) { value in
                            Label(value.title, systemImage: value.systemImage)
                                .tag(value)
                        }
                    }
                    .accessibilityIdentifier("new-card-column")
                }

                Section {
                    Text("This creates a GitHub issue and applies exactly one board column label.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("New card")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Creating" : "Create") {
                        Task { await create() }
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
                    .accessibilityLabel("Create card")
                    .accessibilityIdentifier("confirm-create-card")
                }
            }
        }
    }

    private func create() async {
        isSaving = true
        defer { isSaving = false }
        if await model.createCard(title: title, body: bodyText, column: column) {
            dismiss()
        }
    }
}

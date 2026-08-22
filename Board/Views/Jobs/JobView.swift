import SwiftUI

struct JobView: View {
    @Environment(AppModel.self) private var model
    let jobID: UUID

    var body: some View {
        Group {
            if let job = model.job(id: jobID) {
                content(job)
            } else {
                ProgressView("Loading job")
            }
        }
        .navigationTitle("Job")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: jobID) {
            await model.watchJob(id: jobID)
        }
    }

    private func content(_ job: JobRecord) -> some View {
        VStack(spacing: 0) {
            jobHeader(job)
            Divider()
            logView
        }
        .background(Color(.systemGroupedBackground))
        .safeAreaInset(edge: .bottom) {
            if job.status.isActive {
                Button(role: .destructive) {
                    Task { await model.cancelJob(id: job.id) }
                } label: {
                    Label(job.status == .cancelling ? "Cancelling" : "Cancel job", systemImage: "stop.fill")
                        .frame(maxWidth: .infinity, minHeight: 48)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(job.status == .cancelling)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.bar)
                .accessibilityIdentifier("cancel-job-button")
            }
        }
    }

    private func jobHeader(_ job: JobRecord) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(job.harness.title, systemImage: job.harness.systemImage)
                    .font(.headline)
                Spacer()
                StatusPill(status: job.status)
                    .accessibilityIdentifier("job-status")
            }

            LabeledContent("Repository", value: job.repo)
            LabeledContent("Issue", value: "#\(job.issue)")
            LabeledContent("Branch") {
                Text(job.branch)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                    .multilineTextAlignment(.trailing)
            }

            if job.crew.count > 1 {
                LabeledContent("Run order", value: job.crew.map(\.title).joined(separator: " → "))
            }

            Label(job.outcomeSummary, systemImage: job.outcomeSystemImage)
                .font(.subheadline)
                .foregroundStyle(outcomeColour(for: job))
                .fixedSize(horizontal: false, vertical: true)

            if let error = job.error, job.status == .failed {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }

            if let prURL = job.prURL {
                Link(destination: prURL) {
                    Label("Open pull request", systemImage: "arrow.up.right.square")
                        .font(.body.weight(.semibold))
                }
                .accessibilityIdentifier("job-pr-link")
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .accessibilityElement(children: .contain)
    }

    private func outcomeColour(for job: JobRecord) -> Color {
        if job.hasUnverifiedSuccess {
            return .orange
        }
        return job.status.tint
    }

    private var logView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 7) {
                    let events = model.eventsByJob[jobID, default: []]
                    if events.isEmpty {
                        Text("Waiting for server output.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, minHeight: 160)
                    } else {
                        ForEach(events) { event in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(event.timestamp, format: .dateTime.hour().minute().second())
                                    .foregroundStyle(.tertiary)
                                Text(event.line)
                                    .foregroundStyle(event.kind == .status ? .primary : .secondary)
                                    .textSelection(.enabled)
                            }
                            .font(.caption.monospaced())
                            .accessibilityElement(children: .combine)
                        }
                    }

                    Color.clear
                        .frame(height: 1)
                        .id(logBottomID)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
            }
            .background(Color(.systemBackground))
            .task(id: model.eventsByJob[jobID, default: []].count) {
                guard !model.eventsByJob[jobID, default: []].isEmpty else { return }
                await Task.yield()
                proxy.scrollTo(logBottomID, anchor: .bottom)
            }
            .accessibilityLabel("Job log")
            .accessibilityIdentifier("job-log")
        }
    }

    private var logBottomID: String {
        "job-log-bottom-\(jobID.uuidString)"
    }
}

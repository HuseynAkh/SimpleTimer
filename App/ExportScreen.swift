import SwiftUI
import UniformTypeIdentifiers

struct ExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json, .plainText] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}
struct ExportScreen: View {
    @EnvironmentObject private var store: TimerStore
    @State private var range = 30
    @State private var names = false
    @State private var preparedReport: PreparedReport?
    @State private var exporting = false
    @State private var importing = false
    @State private var document = ExportDocument(data: Data())
    @State private var pending: HistoryBackup?
    @State private var message: String?
    var body: some View {
        Form {
            Section {
                Picker("Include", selection: $range) { Text("Last 7 days").tag(7); Text("Last 30 days").tag(30); Text("All history").tag(0) }
                Toggle("Include session names", isOn: $names)
                Button { makeReport() } label: { Label("Preview AI report", systemImage: "sparkles") }
            } header: { Text("Share with AI") } footer: {
                Text("Preview a plain-text report, then share or save it and attach it in ChatGPT, Claude, or another app. Nothing is sent automatically. Reports include dates and durations; names are optional.")
            }
            Section {
                Button("Save history backup") {
                    do { document = ExportDocument(data: try HistoryBackup(records: store.state.records(at: Date())).encoded()); exporting = true }
                    catch { message = error.localizedDescription }
                }
                Button("Import history backup") { importing = true }
            } header: { Text("Backup") } footer: { Text("JSON backups include all finished sessions and their names. Import adds missing sessions without replacing your timer or settings.") }
        }
        .navigationTitle("Export & backup").navigationBarTitleDisplayMode(.inline)
        .sheet(item: $preparedReport) { report in ReportPreview(report: report) }
        .fileExporter(isPresented: $exporting, document: document, contentType: .json, defaultFilename: "SimpleTimer-history") { result in
            if case .failure(let error) = result { message = error.localizedDescription }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            do {
                let url = try result.get(); let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size <= 20_000_000 else { throw ExportError.invalidBackup }
                pending = try HistoryBackup.decode(Data(contentsOf: url))
            } catch { message = error.localizedDescription }
        }
        .confirmationDialog("Add \(pending?.records.count ?? 0) sessions? Existing records are kept and duplicates skipped.", isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }), titleVisibility: .visible) {
            Button("Import history") { if let pending { let count = store.state.mergeHistory(pending); store.save(); message = "Added \(count) sessions." }; pending = nil }
        }
        .alert("History", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) { Button("OK") { message = nil } } message: { Text(message ?? "") }
    }
    private func makeReport() {
        let now = Date(), cutoff = Calendar.current.date(byAdding: .day, value: -range, to: Date())!
        let records = store.state.records(at: now).filter { range == 0 || $0.startedAt >= cutoff }
        let report = HistoryExport.markdown(records: records, now: now, includeNames: names)
        do {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("SimpleTimer-exports", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            // Keep only the current report in the app's temporary export directory.
            for old in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) { try FileManager.default.removeItem(at: old) }
            let url = directory.appendingPathComponent("SimpleTimer-report.md")
            try Data(report.utf8).write(to: url, options: .atomic)
            preparedReport = PreparedReport(text: report, url: url, records: records.filter(\.isFinished).sorted { $0.startedAt > $1.startedAt }, includeNames: names)
        } catch { message = error.localizedDescription }
    }
}

private struct PreparedReport: Identifiable {
    let id = UUID()
    let text: String
    let url: URL
    let records: [SessionRecord]
    let includeNames: Bool
}
private struct ReportPreview: View {
    let report: PreparedReport
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false
    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("Sessions", value: "\(report.records.count)")
                    LabeledContent("Active time", value: activityDuration(report.records.reduce(0) { $0 + $1.elapsed }))
                    LabeledContent("Session names", value: report.includeNames ? "Included" : "Hidden")
                } footer: { Text("Only finished sessions are included. Pauses are excluded from active time. Dates below use UTC.") }
                Section("Sessions in this report") {
                    ForEach(report.records) { record in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(report.includeNames ? record.preset.name : record.isBreak ? "Break" : "Focus").font(.headline)
                            Text("\(activityDuration(record.elapsed)) of \(activityDuration(record.planned)) · \(record.pauses) pauses · \(record.outcome.rawValue)").font(.subheadline)
                            Text("Started \(record.startedAt.formatted(.iso8601))\nFinished \(record.finishedAt.formatted(.iso8601))").font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                        }.padding(.vertical, 4)
                    }
                }
            }
                .navigationTitle("AI report").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                    ToolbarItem(placement: .primaryAction) { ShareLink(item: report.url) { Label("Share", systemImage: "square.and.arrow.up") } }
                    ToolbarItem(placement: .bottomBar) { Button(copied ? "Copied" : "Copy report") { UIPasteboard.general.string = report.text; copied = true } }
                }
        }
    }
}

import Foundation

/// Plain-text notes file. One file, no database, openable by anything.
struct NotesStore {
    let url: URL

    init() {
        if let override = ProcessInfo.processInfo.environment["NOTCHSLIP_FILE"], !override.isEmpty {
            url = URL(fileURLWithPath: override)
            return
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        let directory = base.appendingPathComponent("NotchSlip", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        url = directory.appendingPathComponent("notes.txt")
    }

    func load() -> String {
        (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    func save(_ text: String) {
        guard let data = text.data(using: .utf8) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
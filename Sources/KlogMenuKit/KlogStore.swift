import AppKit
import Foundation
import ServiceManagement

public struct TaskSummary: Identifiable {
    public let name: String
    public var weekMinutes = 0
    public var lastUse = 0
    public var lastDescription = ""
    public var id: String { name }
}

public struct ProjectSummary: Identifiable {
    public var name: String
    public var weekMinutes = 0
    public var lastUse = 0
    public var tasks: [TaskSummary] = []
    public var id: String { name.lowercased() }

    public func matches(_ other: String?) -> Bool {
        other?.lowercased() == id
    }
}

public struct RunningEntry {
    public let project: String?
    public let task: String
    public let notes: [String]
    public let start: Date
    public let recordDate: String
    public var description: String { notes.joined(separator: "\n") }
}

public enum LogDay: String, CaseIterable, Identifiable {
    case today = "Today"
    case yesterday = "Yesterday"
    public var id: String { rawValue }
}

@MainActor
public final class KlogStore: ObservableObject {
    @Published public private(set) var projects: [ProjectSummary] = []
    @Published public private(set) var running: RunningEntry?
    @Published public private(set) var todayClosedMinutes = 0
    @Published public private(set) var weekClosedMinutes = 0
    @Published public private(set) var now = Date()
    @Published public private(set) var fileProblem: String?
    @Published public var actionError: String?
    @Published public var confirmation: String?

    @Published public var filePath: String {
        didSet {
            UserDefaults.standard.set(filePath, forKey: "filePath")
            refresh()
        }
    }

    private var lastModification: Date?
    private var timer: Timer?

    static let defaultFilePath = NSHomeDirectory() + "/timetrack/time.klg"

    public init(filePath: String? = nil) {
        self.filePath = filePath ?? UserDefaults.standard.string(forKey: "filePath") ?? Self.defaultFilePath
        _ = Klog.supportsNote
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    public var runningMinutes: Int {
        guard let running else { return 0 }
        return max(0, Int(now.timeIntervalSince(running.start) / 60))
    }

    public var todayMinutes: Int { todayClosedMinutes + runningMinutes }
    public var weekMinutes: Int { weekClosedMinutes + runningMinutes }

    public func weekMinutes(project: ProjectSummary) -> Int {
        project.weekMinutes + (project.matches(running?.project) ? runningMinutes : 0)
    }

    public func weekMinutes(task: TaskSummary, in project: ProjectSummary) -> Int {
        let matches = project.matches(running?.project) && running?.task == task.name
        return task.weekMinutes + (matches ? runningMinutes : 0)
    }

    public var menuBarTitle: String {
        if let running {
            let project = running.project ?? "untagged"
            let label = running.task.isEmpty ? project : "\(project) › \(running.task)"
            return "\(label) \(formatClock(runningMinutes))"
        }
        return formatMinutes(todayMinutes)
    }

    var fileChangedSinceRefresh: Bool { modificationDate() != lastModification }

    private func tick() {
        if fileChangedSinceRefresh {
            refresh()
            return
        }
        let current = Date()
        if Int(current.timeIntervalSinceReferenceDate / 60) != Int(now.timeIntervalSinceReferenceDate / 60) {
            now = current
        }
    }

    private var resolvedFilePath: String {
        URL(fileURLWithPath: filePath).resolvingSymlinksInPath().path
    }

    private func modificationDate() -> Date? {
        try? FileManager.default.attributesOfItem(atPath: resolvedFilePath)[.modificationDate] as? Date
    }

    public func refresh() {
        now = Date()
        lastModification = modificationDate()
        guard FileManager.default.fileExists(atPath: filePath) else {
            apply(records: [])
            fileProblem = nil
            return
        }
        do {
            let output = try Klog.run(["json", filePath])
            let parsed = try JSONDecoder().decode(KlogJSON.self, from: Data(output.utf8))
            if let errors = parsed.errors, !errors.isEmpty {
                let first = errors[0]
                let line = first.line.map { "line \($0): " } ?? ""
                fileProblem = "\(line)\(first.title ?? "Syntax error"). Open the file to fix it."
                return
            }
            fileProblem = nil
            apply(records: parsed.records ?? [])
        } catch {
            fileProblem = error.localizedDescription
        }
    }

    private static let dateParser: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private func apply(records: [KlogJSON.Record]) {
        let calendar = Calendar(identifier: .iso8601)
        let today = calendar.startOfDay(for: now)
        let week = calendar.dateInterval(of: .weekOfYear, for: now)
        var projectMap: [String: ProjectSummary] = [:]
        var todayTotal = 0
        var weekTotal = 0
        var foundRunning: RunningEntry?
        var order = 0

        let sorted = records.sorted { $0.date < $1.date }
        for record in sorted {
            guard let day = Self.dateParser.date(from: record.date.replacingOccurrences(of: "/", with: "-")) else { continue }
            let inWeek = week?.contains(day) ?? false
            let isToday = calendar.isDate(day, inSameDayAs: today)
            for entry in record.entries {
                order += 1
                let parsed = Klog.firstTag(in: entry.summary) ?? record.summary.flatMap(Klog.firstTag)
                let projectName = parsed?.name
                let taskName = parsed?.value ?? ""
                let description = Klog.stripTags(entry.summary)

                if entry.type == "open_range", let startMinutes = entry.start_mins {
                    foundRunning = RunningEntry(
                        project: projectName,
                        task: taskName,
                        notes: entry.summary.components(separatedBy: .newlines).map(Klog.stripTags).filter { !$0.isEmpty },
                        start: day.addingTimeInterval(TimeInterval(startMinutes * 60)),
                        recordDate: record.date
                    )
                }

                let minutes = entry.total_mins
                if isToday { todayTotal += minutes }
                if inWeek { weekTotal += minutes }

                guard let projectName else { continue }
                let key = projectName.lowercased()
                var project = projectMap[key] ?? ProjectSummary(name: projectName)
                project.name = projectName
                project.lastUse = order
                if inWeek { project.weekMinutes += minutes }
                var task = project.tasks.first { $0.name == taskName } ?? TaskSummary(name: taskName)
                task.lastUse = order
                if !description.isEmpty { task.lastDescription = description }
                if inWeek { task.weekMinutes += minutes }
                project.tasks.removeAll { $0.name == taskName }
                project.tasks.append(task)
                projectMap[key] = project
            }
        }

        projects = projectMap.values
            .map { project in
                var sortedProject = project
                sortedProject.tasks.sort { $0.lastUse > $1.lastUse }
                return sortedProject
            }
            .sorted { $0.lastUse > $1.lastUse }
        running = foundRunning
        todayClosedMinutes = todayTotal
        weekClosedMinutes = weekTotal
    }

    private func ensureFileExists() throws {
        let url = URL(fileURLWithPath: filePath)
        if FileManager.default.fileExists(atPath: filePath) { return }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: url)
    }

    private func perform(_ arguments: [String], confirmation message: String) -> Bool {
        do {
            try ensureFileExists()
            try Klog.run(arguments + ["--no-style", filePath])
            actionError = nil
            confirmation = message
            refresh()
            return true
        } catch {
            actionError = error.localizedDescription
            return false
        }
    }

    private func label(project: String, task: String) -> String {
        task.isEmpty ? project : "\(project) › \(task)"
    }

    public func log(project: String, task: String, description: String, amount: String, day: LogDay) -> Bool {
        guard let normalized = Klog.normalizeAmount(amount) else {
            actionError = "Use a duration like 1h30m or 45m, or a range like 9:00-10:30."
            return false
        }
        let entry = "\(normalized) \(Klog.summary(project: project, task: task, description: description))"
        var arguments = ["track", entry]
        if day == .yesterday { arguments.append("--yesterday") }
        return perform(arguments, confirmation: "Logged \(normalized) to \(label(project: project, task: task))")
    }

    public func start(project: String, task: String, description: String, at time: String) -> Bool {
        let summary = Klog.summary(project: project, task: task, description: description)
        var arguments = [running == nil ? "start" : "switch", "--summary=\(summary)"]
        let trimmedTime = time.trimmingCharacters(in: .whitespaces)
        if !trimmedTime.isEmpty { arguments.append("--time=\(trimmedTime)") }
        return perform(arguments, confirmation: "Started \(label(project: project, task: task))")
    }

    public func appendNote(_ note: String) -> Bool {
        let text = note.components(separatedBy: .newlines).joined(separator: " ").trimmingCharacters(in: .whitespaces)
        guard let running, !text.isEmpty else { return false }
        if Klog.supportsNote {
            let escaped = text.hasPrefix("-") ? "\\" + text : text
            return perform(["note", escaped, "--date=\(running.recordDate)"], confirmation: "Added note")
        }
        do {
            let original = try String(contentsOfFile: resolvedFilePath, encoding: .utf8)
            guard let updated = Klog.insertNote(text, intoOpenRangeOf: running.recordDate, in: original) else {
                actionError = "Could not find the running entry in the file."
                return false
            }
            try updated.write(toFile: resolvedFilePath, atomically: true, encoding: .utf8)
            let check = try? JSONDecoder().decode(KlogJSON.self, from: Data(Klog.run(["json", filePath]).utf8))
            let openSummary = check?.records?.flatMap(\.entries).first { $0.type == "open_range" }?.summary
            guard check?.errors?.isEmpty ?? true, openSummary?.hasSuffix(text) == true else {
                try original.write(toFile: resolvedFilePath, atomically: true, encoding: .utf8)
                actionError = "Adding the note would have broken the file, so it was not saved."
                refresh()
                return false
            }
            actionError = nil
            confirmation = "Added note"
            refresh()
            return true
        } catch {
            actionError = error.localizedDescription
            return false
        }
    }

    public func stop() {
        guard let running else { return }
        let name = label(project: running.project ?? "entry", task: running.task)
        _ = perform(["stop"], confirmation: "Stopped \(name) after \(formatMinutes(runningMinutes))")
    }

    public func openFile() {
        try? ensureFileExists()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-t", filePath]
        try? process.run()
    }

    public func chooseFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: filePath).deletingLastPathComponent()
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK, let url = panel.url {
            filePath = url.path
        }
    }

    public var launchesAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                actionError = "Could not change login item: \(error.localizedDescription)"
            }
            objectWillChange.send()
        }
    }
}

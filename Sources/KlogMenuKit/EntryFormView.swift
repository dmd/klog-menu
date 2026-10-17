import SwiftUI

public struct EntryFormView: View {
    @ObservedObject var store: KlogStore
    let draft: EntryDraft
    let onClose: () -> Void

    @State private var project = ""
    @State private var task = ""
    @State private var description = ""
    @State private var customAmount = ""
    @State private var startTime = ""
    @State private var day: LogDay = .today
    @FocusState private var focused: Field?

    private enum Field { case project, task, description }

    private let presets = [["15m", "30m", "45m", "1h"], ["1h30m", "2h", "3h", "4h"]]

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button(action: onClose) { Image(systemName: "chevron.left") }
                    .buttonStyle(.borderless)
                    .keyboardShortcut(.cancelAction)
                Text(heading).font(.headline).lineLimit(1)
                Spacer()
            }

            if draft.editableProject {
                TextField("Project (e.g. abcd)", text: $project)
                    .focused($focused, equals: .project)
                if !project.isEmpty && cleanedProject != project.trimmingCharacters(in: .whitespaces) {
                    Text("Will be saved as #\(cleanedProject)")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if draft.editableTask {
                TextField("Task (optional)", text: $task)
                    .focused($focused, equals: .task)
            }
            TextField(
                draft.lastDescription.isEmpty ? "Description (optional)" : "Last: \(draft.lastDescription)",
                text: $description
            )
            .focused($focused, equals: .description)

            if let error = store.actionError {
                Label(error, systemImage: "xmark.octagon.fill")
                    .font(.callout).foregroundStyle(.red)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Log time spent").font(.subheadline.weight(.medium))
                        Spacer()
                        Picker("", selection: $day) {
                            ForEach(LogDay.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .fixedSize()
                    }
                    ForEach(presets, id: \.self) { row in
                        HStack(spacing: 6) {
                            ForEach(row, id: \.self) { amount in
                                Button(amount) { log(amount) }
                                    .frame(maxWidth: .infinity)
                                    .disabled(!canSubmit)
                            }
                        }
                    }
                    HStack(spacing: 6) {
                        TextField("Other: 1h20m or 9:00-10:30", text: $customAmount)
                            .onSubmit { log(customAmount) }
                        Button("Log") { log(customAmount) }
                            .disabled(!canSubmit || customAmount.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
                .padding(4)
            }

            GroupBox {
                HStack(spacing: 6) {
                    Text(store.running == nil ? "Start timer" : "Switch timer")
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    Text("at").foregroundStyle(.secondary)
                    TextField("now", text: $startTime)
                        .frame(width: 56)
                        .onSubmit(start)
                    Button(store.running == nil ? "Start" : "Switch", action: start)
                        .disabled(!canSubmit)
                }
                .padding(4)
            }
        }
        .onAppear {
            project = draft.project
            task = draft.task
            store.actionError = nil
            let field: Field = draft.editableProject ? .project : (draft.editableTask ? .task : .description)
            DispatchQueue.main.async { focused = field }
        }
    }

    private var heading: String {
        if draft.editableProject { return "New project" }
        if draft.editableTask { return "New task in \(draft.project)" }
        return draft.task.isEmpty ? draft.project : "\(draft.project) › \(draft.task)"
    }

    private var cleanedProject: String { Klog.cleanProject(project) }
    private var cleanedTask: String { Klog.cleanTask(task) }
    private var canSubmit: Bool { !cleanedProject.isEmpty }

    private func log(_ amount: String) {
        guard canSubmit else { return }
        if store.log(project: cleanedProject, task: cleanedTask, description: description, amount: amount, day: day) {
            onClose()
        }
    }

    private func start() {
        guard canSubmit else { return }
        if store.start(project: cleanedProject, task: cleanedTask, description: description, at: startTime) {
            onClose()
        }
    }
}

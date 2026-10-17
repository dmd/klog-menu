import SwiftUI

public struct EntryDraft: Identifiable {
    public let id = UUID()
    public var project: String
    public var task: String
    public var editableProject: Bool
    public var editableTask: Bool
    public var lastDescription: String = ""

    public init(project: String, task: String, editableProject: Bool, editableTask: Bool, lastDescription: String = "") {
        self.project = project
        self.task = task
        self.editableProject = editableProject
        self.editableTask = editableTask
        self.lastDescription = lastDescription
    }
}

public struct MenuView: View {
    @ObservedObject var store: KlogStore
    @State private var draft: EntryDraft?
    @State private var collapsed: Set<String>

    public init(store: KlogStore, draft: EntryDraft? = nil, collapsed: Set<String> = []) {
        self.store = store
        _draft = State(initialValue: draft)
        _collapsed = State(initialValue: collapsed)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let draft {
                EntryFormView(store: store, draft: draft) { self.draft = nil }
            } else {
                mainContent
            }
        }
        .padding(12)
        .frame(width: 340)
        .background(TopAnchor())
        .onAppear {
            NSApp.activate()
            store.refresh()
            store.confirmation = nil
            store.actionError = nil
            if let project = store.running?.project { collapsed.remove(project.lowercased()) }
        }
        .onDisappear { draft = nil }
    }

    @ViewBuilder
    private var mainContent: some View {
        if let running = store.running {
            RunningBanner(store: store, running: running)
        }

        HStack {
            Text("Today \(formatMinutes(store.todayMinutes))")
            Text("·").foregroundStyle(.tertiary)
            Text("This week \(formatMinutes(store.weekMinutes))")
            Spacer()
        }
        .font(.callout)
        .foregroundStyle(.secondary)

        if let confirmation = store.confirmation {
            Label(confirmation, systemImage: "checkmark.circle.fill")
                .font(.callout)
                .foregroundStyle(.green)
        }
        if let problem = store.fileProblem {
            Label(problem, systemImage: "exclamationmark.triangle.fill")
                .font(.callout)
                .foregroundStyle(.orange)
        }
        if let error = store.actionError {
            Label(error, systemImage: "xmark.octagon.fill")
                .font(.callout)
                .foregroundStyle(.red)
        }

        Divider()

        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(store.projects) { project in
                    projectSection(project)
                }
                HoverRow(action: {
                    draft = EntryDraft(project: "", task: "", editableProject: true, editableTask: true)
                }) {
                    Label("New project…", systemImage: "plus")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }
        }
        .frame(maxHeight: 420)
        .fixedSize(horizontal: false, vertical: true)

        Divider()

        HStack {
            Button("Open file") { store.openFile() }
            Spacer()
            Menu {
                Text(store.filePath)
                Button("Choose file…") { store.chooseFile() }
                Toggle("Launch at login", isOn: Binding(
                    get: { store.launchesAtLogin },
                    set: { store.launchesAtLogin = $0 }
                ))
                Divider()
                Button("Quit klog-menu") { NSApp.terminate(nil) }
            } label: {
                Image(systemName: "gearshape")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .buttonStyle(.borderless)
    }

    @ViewBuilder
    private func projectSection(_ project: ProjectSummary) -> some View {
        let isExpanded = !collapsed.contains(project.id)
        let namedTasks = project.tasks.filter { !$0.name.isEmpty }
        let untaskedDescription = project.tasks.first { $0.name.isEmpty }?.lastDescription ?? ""
        HStack(spacing: 0) {
            Button {
                if isExpanded { collapsed.insert(project.id) } else { collapsed.remove(project.id) }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            HoverRow(action: {
                draft = EntryDraft(
                    project: project.name, task: "",
                    editableProject: false, editableTask: false,
                    lastDescription: untaskedDescription
                )
            }) {
                Text(project.name).fontWeight(.medium)
                if project.matches(store.running?.project) {
                    Image(systemName: "record.circle").foregroundStyle(.red).font(.caption)
                }
                Spacer()
                Text(formatMinutes(store.weekMinutes(project: project)))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }

        if isExpanded {
            ForEach(namedTasks) { task in
                HoverRow(action: {
                    draft = EntryDraft(
                        project: project.name, task: task.name,
                        editableProject: false, editableTask: false,
                        lastDescription: task.lastDescription
                    )
                }) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(task.name)
                        if !task.lastDescription.isEmpty {
                            Text(task.lastDescription)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    if project.matches(store.running?.project) && store.running?.task == task.name {
                        Image(systemName: "record.circle").foregroundStyle(.red).font(.caption)
                    }
                    Spacer()
                    Text(formatMinutes(store.weekMinutes(task: task, in: project)))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                .padding(.leading, 20)
            }
            HoverRow(action: {
                draft = EntryDraft(project: project.name, task: "", editableProject: false, editableTask: true)
            }) {
                Label("New task…", systemImage: "plus")
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.leading, 20)
        }
    }
}

public struct RunningBanner: View {
    @ObservedObject var store: KlogStore
    let running: RunningEntry
    @State private var note = ""
    @FocusState private var noteFocused: Bool

    private let visibleNotes = 4

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: "record.circle").foregroundStyle(.red)
                Text(title).fontWeight(.medium).lineLimit(1)
                Spacer()
                Text(formatClock(store.runningMinutes))
                    .monospacedDigit()
                    .font(.title3)
                Button("Stop") { store.stop() }
            }
            if !running.notes.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    if running.notes.count > visibleNotes {
                        Text("\(running.notes.count - visibleNotes) earlier")
                            .foregroundStyle(.tertiary)
                    }
                    ForEach(Array(running.notes.suffix(visibleNotes).enumerated()), id: \.offset) { _, line in
                        Text(line).foregroundStyle(.secondary).lineLimit(2)
                    }
                }
                .font(.caption)
                .padding(.leading, 24)
            }
            TextField("Add a note…", text: $note)
                .focused($noteFocused)
                .onSubmit {
                    if store.appendNote(note) { note = "" }
                }
                .padding(.leading, 24)
        }
        .padding(8)
        .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        .onAppear { DispatchQueue.main.async { noteFocused = true } }
    }

    private var title: String {
        let project = running.project ?? "Untagged"
        return running.task.isEmpty ? project : "\(project) › \(running.task)"
    }
}

public struct HoverRow<Content: View>: View {
    let action: () -> Void
    @ViewBuilder let content: () -> Content
    @State private var hovering = false

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 6) { content() }
                .padding(.vertical, 4)
                .padding(.horizontal, 6)
                .contentShape(Rectangle())
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(hovering ? Color.accentColor.opacity(0.15) : .clear)
                )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

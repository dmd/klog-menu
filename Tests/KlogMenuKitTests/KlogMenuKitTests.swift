import AppKit
import SwiftUI
import XCTest
@testable import KlogMenuKit

@MainActor
final class KlogMenuKitTests: XCTestCase {
    private var directory: URL!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func day(_ offset: Int) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Calendar.current.date(byAdding: .day, value: offset, to: Date())!)
    }

    private func makeFile(_ contents: String) throws -> String {
        let path = directory.appendingPathComponent("time.klg").path
        try contents.write(toFile: path, atomically: true, encoding: .utf8)
        return path
    }

    private func contents(_ path: String) throws -> String {
        try String(contentsOfFile: path, encoding: .utf8)
    }

    func testHelpers() {
        XCTAssertEqual(Klog.cleanProject("My Big Project!"), "my-big-project")
        XCTAssertEqual(Klog.tagValue("comms"), "comms")
        XCTAssertEqual(Klog.tagValue("b-vector check"), "\"b-vector check\"")
        XCTAssertEqual(Klog.tagValue("v1.2"), "\"v1.2\"")
        XCTAssertEqual(Klog.summary(project: "abcd", task: "", description: ""), "#abcd")
        XCTAssertEqual(Klog.summary(project: "abcd", task: "qc run", description: "did it"), "did it #abcd=\"qc run\"")
        XCTAssertEqual(Klog.normalizeAmount("1h30m"), "1h30m")
        XCTAssertEqual(Klog.normalizeAmount("9:00-10:30"), "9:00 - 10:30")
        XCTAssertNil(Klog.normalizeAmount("1.5h"))
        XCTAssertNil(Klog.normalizeAmount(""))
        XCTAssertEqual(Klog.stripTags("emailed #abcd=\"x y\" vendor #foo"), "emailed vendor")
        XCTAssertEqual(Klog.stripTags("drafted aim 2 #grant-writing=\"aims page\""), "drafted aim 2")
        XCTAssertEqual(Klog.parseTag("#ABCD=\"two words\"").name, "abcd")
        XCTAssertEqual(Klog.parseTag("#ABCD=\"two words\"").value, "two words")
    }

    func testParsesProjectsAndTasks() throws {
        let path = try makeFile("""
        \(day(-30))
            5h old work #legacy=thing

        \(day(0))
            2h Review slices #dmri=qc
            1h #abcd=comms
            30m emailed vendor #abcd=comms
            45m #dmri="b-vector check"
        """)
        let store = KlogStore(filePath: path)
        XCTAssertNil(store.fileProblem)
        XCTAssertEqual(store.projects.map(\.name), ["dmri", "abcd", "legacy"])
        let dmri = store.projects[0]
        XCTAssertEqual(dmri.weekMinutes, 165)
        XCTAssertEqual(dmri.tasks.map(\.name), ["b-vector check", "qc"])
        let abcd = store.projects[1]
        XCTAssertEqual(abcd.tasks.first?.lastDescription, "emailed vendor")
        XCTAssertEqual(abcd.weekMinutes, 90)
        XCTAssertEqual(store.projects[2].weekMinutes, 0)
        XCTAssertEqual(store.todayMinutes, 255)
        XCTAssertNil(store.running)
        XCTAssertEqual(store.menuBarTitle, "4h15m")
    }

    func testLogStartSwitchStop() throws {
        let path = directory.appendingPathComponent("sub/time.klg").path
        let store = KlogStore(filePath: path)
        XCTAssertTrue(store.projects.isEmpty)

        XCTAssertTrue(store.log(project: "abcd", task: "comms", description: "wrote email", amount: "45m", day: .today))
        XCTAssertTrue(store.log(project: "new-proj", task: "two words", description: "", amount: "9:00-10:00", day: .yesterday))
        XCTAssertFalse(store.log(project: "abcd", task: "", description: "", amount: "lots", day: .today))
        XCTAssertNotNil(store.actionError)

        var text = try contents(path)
        XCTAssertTrue(text.contains("45m wrote email #abcd=comms"), text)
        XCTAssertTrue(text.contains("\(day(-1))\n    9:00 - 10:00 #new-proj=\"two words\""), text)
        XCTAssertEqual(store.projects.map(\.name), ["abcd", "new-proj"])

        XCTAssertTrue(store.start(project: "abcd", task: "", description: "thinking", at: "8:00"))
        XCTAssertEqual(store.running?.project, "abcd")
        XCTAssertEqual(store.running?.task, "")
        XCTAssertEqual(store.running?.description, "thinking")
        XCTAssertTrue(store.menuBarTitle.hasPrefix("abcd 0:00") || store.menuBarTitle.hasPrefix("abcd "), store.menuBarTitle)
        XCTAssertFalse(store.menuBarTitle.contains("›"), store.menuBarTitle)

        XCTAssertTrue(store.start(project: "dmri", task: "qc", description: "", at: ""))
        XCTAssertEqual(store.running?.project, "dmri")
        XCTAssertEqual(store.running?.task, "qc")
        XCTAssertTrue(store.menuBarTitle.hasPrefix("dmri › qc 0:0"), store.menuBarTitle)
        text = try contents(path)
        XCTAssertTrue(text.contains("8:00 - "), text)

        store.stop()
        XCTAssertNil(store.running)
        XCTAssertNil(store.actionError)
        text = try contents(path)
        XCTAssertFalse(text.contains("?"), text)
        print(text)
    }

    private func checkAppendNoteToRunningEntry() throws {
        let path = try makeFile("""
        \(day(-1))
            9:00 - 10:00 #other
                yesterday line

        \(day(0))
            8:00 - 9:00 earlier #abcd
            9:00 - ?
            30m after #dmri
        """)
        let store = KlogStore(filePath: path)
        XCTAssertNotNil(store.running)
        XCTAssertTrue(store.appendNote("first note #abcd"))
        XCTAssertTrue(store.appendNote("second note"))
        XCTAssertFalse(store.appendNote("   "))
        XCTAssertEqual(store.running?.notes, ["first note", "second note"])
        XCTAssertEqual(store.running?.project, "abcd")
        let text = try contents(path)
        XCTAssertTrue(text.contains("""
            9:00 - ?
                first note #abcd
                second note
            30m after #dmri
        """), text)
        XCTAssertTrue(text.contains("    9:00 - 10:00 #other\n        yesterday line\n"), text)

        store.stop()
        XCTAssertFalse(store.appendNote("too late"))
    }

    func testAppendNoteWithKlogNote() throws {
        try XCTSkipUnless(Klog.supportsNote, "installed klog has no note command")
        try checkAppendNoteToRunningEntry()
    }

    func testAppendNoteByEditingFile() throws {
        let saved = Klog.supportsNote
        Klog.supportsNote = false
        defer { Klog.supportsNote = saved }
        try checkAppendNoteToRunningEntry()
    }

    func testSymlinkedFileStaysLinked() throws {
        let realPath = try makeFile("\(day(0))\n    9:00 - ? #abcd\n")
        let linkPath = directory.appendingPathComponent("link.klg").path
        try FileManager.default.createSymbolicLink(atPath: linkPath, withDestinationPath: realPath)
        let saved = Klog.supportsNote
        Klog.supportsNote = false
        defer { Klog.supportsNote = saved }

        let store = KlogStore(filePath: linkPath)
        XCTAssertTrue(store.appendNote("through the link"), store.actionError ?? "")
        XCTAssertNotNil(try? FileManager.default.destinationOfSymbolicLink(atPath: linkPath))
        XCTAssertTrue(try contents(realPath).contains("        through the link"))

        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -3600)], ofItemAtPath: realPath)
        store.refresh()
        try Klog.run(["track", "1h #frog-pond", realPath])
        XCTAssertTrue(store.fileChangedSinceRefresh)
    }

    func testAppendNoteStartingWithDash() throws {
        let path = try makeFile("\(day(0))\n    9:00 - ? #abcd\n")
        let store = KlogStore(filePath: path)
        XCTAssertTrue(store.appendNote("-45 degrees outside"), store.actionError ?? "")
        XCTAssertEqual(store.running?.notes, ["-45 degrees outside"])
    }

    func testAppendNoteWithTabsAndInlineSummary() throws {
        XCTAssertEqual(
            Klog.insertNote("more", intoOpenRangeOf: "2026-10-16", in: "2026/10/16\n\t9:00 - ? x #abcd\n\t\tline\n"),
            "2026/10/16\n\t9:00 - ? x #abcd\n\t\tline\n\t\tmore\n"
        )
        XCTAssertNil(Klog.insertNote("more", intoOpenRangeOf: "2026-10-16", in: "2026-10-16\n    9:00 - 10:00 x\n"))
    }

    func testReportsSyntaxErrors() throws {
        let path = try makeFile("\(day(0))\n    garbage line\n")
        let store = KlogStore(filePath: path)
        XCTAssertNotNil(store.fileProblem)
        XCTAssertTrue(store.fileProblem!.contains("line 2"), store.fileProblem!)
    }

    func testRenderSnapshots() throws {
        guard let output = ProcessInfo.processInfo.environment["SNAPSHOT_DIR"] else {
            throw XCTSkip("Set SNAPSHOT_DIR to render snapshots")
        }
        let path = try makeFile("""
        \(day(-1))
            2h Review slices #dmri=qc
            1h #abcd=comms

        \(day(0))
            16:00 - 17:00 contacted Lasso and NBCD #abcd=comms
            1h30m pipeline debugging #dmri="b-vector check"
            30m #home=chores
        """)
        let store = KlogStore(filePath: path)
        XCTAssertTrue(store.start(project: "dmri", task: "qc", description: "second pass on slices", at: ""))

        let snapshots: [(String, AnyView)] = [
            ("main", AnyView(MenuView(store: store, collapsed: ["home"]))),
            ("task-form", AnyView(MenuView(store: store, draft: EntryDraft(
                project: "abcd", task: "comms", editableProject: false, editableTask: false,
                lastDescription: "contacted Lasso and NBCD")))),
            ("new-project-form", AnyView(MenuView(store: store, draft: EntryDraft(
                project: "", task: "", editableProject: true, editableTask: true)))),
        ]
        for (name, view) in snapshots {
            let renderer = ImageRenderer(content: view.background(Color(nsColor: .windowBackgroundColor)))
            renderer.scale = 2
            guard let image = renderer.cgImage else { return XCTFail("no image for \(name)") }
            let rep = NSBitmapImageRep(cgImage: image)
            try rep.representation(using: .png, properties: [:])!
                .write(to: URL(fileURLWithPath: output).appendingPathComponent("\(name).png"))
        }
    }
}

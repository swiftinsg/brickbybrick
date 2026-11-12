import SwiftUI
import PhotosUI
import PDFKit
import Vision
import EventKit
import FoundationModels
import UniformTypeIdentifiers

/// One weekly class. `weekday` is Calendar's (1 = Sunday); times are minutes since midnight.
struct Lesson: Identifiable, Equatable {
    var id = UUID()
    var subject: String
    var weekday: Int
    var start: Int
    var end: Int
}

@Generable struct DraftTimetable {
    @Guide(description: "Every lesson in the timetable, one per class on each day", .count(0...80))
    var lessons: [DraftLesson]
}

@Generable struct DraftLesson {
    @Guide(description: "Subject or class name, e.g. \"Maths\" or \"Chemistry lab\"")
    var subject: String
    @Guide(description: "Day of the week", .anyOf(Timetable.weekdays))
    var weekday: String
    @Guide(description: "Start hour, 24-hour clock", .range(0...23)) var startHour: Int
    @Guide(description: "Start minute", .range(0...59)) var startMinute: Int
    @Guide(description: "End hour, 24-hour clock", .range(0...23)) var endHour: Int
    @Guide(description: "End minute", .range(0...59)) var endMinute: Int
}

enum Timetable {
    static let weekdays = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
    private static let savedKey = "timetableEventIDs"

    /// Reads a timetable photo or PDF: Vision finds the table, then the on-device
    /// model turns it into lessons (and also sees the picture, if it can).
    static func read(_ images: [CGImage]) async throws -> [Lesson] {
        var text = ""
        for image in images {
            for doc in try await RecognizeDocumentsRequest().perform(on: image, orientation: nil) {
                let tables = doc.document.tables.map { table in
                    table.rows.map { $0.map(\.content.text.transcript).joined(separator: " | ") }.joined(separator: "\n")
                }
                text += (tables.isEmpty ? doc.document.text.transcript : tables.joined(separator: "\n\n")) + "\n"
            }
        }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw TimetableError.noText }
        let vision = SystemLanguageModel.default.capabilities.contains(.vision)
        let session = LanguageModelSession(instructions: """
            You read a student's school timetable. List every lesson with its day, start and end time. \
            Rows or columns are usually days and periods; a period's times apply to every lesson in it. \
            Times like 1:30 in the afternoon are 13:30. Skip breaks, recess and lunch. \
            A lesson spanning two periods is one lesson from the first start to the last end.
            """)
        let draft = try await session.respond(to: Prompt {
            "Timetable text (cells separated by |):\n\(text)"
            if vision, let first = images.first { Attachment(first) }
        }, generating: DraftTimetable.self).content
        return draft.lessons.compactMap(lesson)
    }

    /// A model lesson as a `Lesson`, or nil if it's a break or has no real time.
    static func lesson(_ d: DraftLesson) -> Lesson? {
        let subject = d.subject.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let day = weekdays.firstIndex(of: d.weekday), !subject.isEmpty,
              !["break", "recess", "lunch"].contains(subject.lowercased()) else { return nil }
        let start = d.startHour * 60 + d.startMinute, end = d.endHour * 60 + d.endMinute
        return end > start ? Lesson(subject: subject, weekday: day + 1, start: start, end: end) : nil
    }

    /// The first time this lesson happens on or after `from`.
    static func firstDate(of lesson: Lesson, from: Date, calendar cal: Calendar = .current) -> Date {
        let day = cal.nextDate(after: cal.startOfDay(for: from).addingTimeInterval(-1),
                               matching: DateComponents(weekday: lesson.weekday), matchingPolicy: .nextTime)!
        return cal.date(byAdding: .minute, value: lesson.start, to: day)!
    }

    /// Weekly repeating events until `until`. A re-import replaces the last one.
    /// The scheduler then treats lessons as busy time, like any Calendar event.
    @MainActor static func addToCalendar(_ lessons: [Lesson], until: Date) async throws {
        guard await CalendarSync.requestAccess() else { throw CalendarError.noAccess }
        let store = CalendarSync.store
        guard let calendar = store.defaultCalendarForNewEvents else { throw CalendarError.noCalendar }
        for id in UserDefaults.standard.stringArray(forKey: savedKey) ?? [] {
            if let old = store.event(withIdentifier: id) { try? store.remove(old, span: .futureEvents, commit: false) }
        }
        var ids: [String] = []
        for lesson in lessons {
            let event = EKEvent(eventStore: store)
            event.calendar = calendar
            event.title = lesson.subject
            event.startDate = firstDate(of: lesson, from: .now)
            event.endDate = event.startDate.addingTimeInterval(TimeInterval((lesson.end - lesson.start) * 60))
            event.notes = "From brickbybrick · School timetable"
            event.addRecurrenceRule(EKRecurrenceRule(recurrenceWith: .weekly, interval: 1,
                                                     end: EKRecurrenceEnd(end: until)))
            try store.save(event, span: .futureEvents, commit: false)
            ids.append(event.eventIdentifier)
        }
        try store.commit()
        UserDefaults.standard.set(ids, forKey: savedKey)
    }
}

enum TimetableError: LocalizedError {
    case noText, unreadable
    var errorDescription: String? {
        switch self {
        case .noText: "Couldn't find any text. Try a clearer, straight-on photo."
        case .unreadable: "Couldn't open that file."
        }
    }
}

/// Settings → School → Add timetable to Calendar. Pick a photo or PDF, check
/// the lessons it found (or type them in), then add them as weekly events.
struct TimetableView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var lessons: [Lesson] = []
    @State private var photo: PhotosPickerItem?
    @State private var pickingFile = false
    @State private var isWorking = false
    @State private var message: String?
    @State private var until = Calendar.current.date(byAdding: .month, value: 3, to: .now)!

    var body: some View {
        Form {
            Section {
                PhotosPicker(selection: $photo, matching: .images) {
                    Label("Choose a photo", systemImage: "photo")
                }
                Button("Choose a PDF or image file", systemImage: "doc") { pickingFile = true }
            } footer: {
                Text(Planner.isAvailable
                     ? "The AI reads it on your iPhone. Check the lessons before adding them."
                     : "Apple Intelligence isn't available, so add your lessons below yourself.")
            }
            .disabled(isWorking || !Planner.isAvailable)

            if isWorking {
                HStack { ProgressView(); Text("Reading your timetable…") }
            }

            Section("Lessons") {
                ForEach($lessons) { $lesson in
                    VStack(alignment: .leading) {
                        TextField("Subject", text: $lesson.subject).font(.headline)
                        Picker("Day", selection: $lesson.weekday) {
                            ForEach(1...7, id: \.self) { Text(Timetable.weekdays[$0 - 1]).tag($0) }
                        }
                        HStack {
                            DatePicker("From", selection: minutes($lesson.start), displayedComponents: .hourAndMinute)
                            DatePicker("to", selection: minutes($lesson.end), displayedComponents: .hourAndMinute)
                        }
                        .labelsHidden()
                    }
                }
                .onDelete { lessons.remove(atOffsets: $0) }
                Button("Add lesson", systemImage: "plus") {
                    let last = lessons.last
                    lessons.append(Lesson(subject: "", weekday: last?.weekday ?? 2,
                                          start: last?.end ?? 8 * 60, end: (last?.end ?? 8 * 60) + 60))
                }
            }

            if !lessons.isEmpty {
                Section {
                    DatePicker("Repeat weekly until", selection: $until, in: Date.now..., displayedComponents: .date)
                    Button("Add \(lessons.count) lesson\(lessons.count == 1 ? "" : "s") to Calendar",
                           systemImage: "calendar.badge.plus") { Task { await add() } }
                        .disabled(isWorking)
                } footer: {
                    if let message { Text(message) }
                    else { Text("Pick the end of term. Adding again replaces the timetable you added before. Plans avoid your lessons.") }
                }
            } else if let message {
                Text(message).foregroundStyle(.red)
            }
        }
        .navigationTitle("School timetable")
        .onChange(of: photo) {
            guard let photo else { return }
            Task {
                await read {
                    guard let data = try await photo.loadTransferable(type: Data.self),
                          let image = UIImage(data: data)?.cgImage else { throw TimetableError.unreadable }
                    return [image]
                }
                self.photo = nil
            }
        }
        .fileImporter(isPresented: $pickingFile, allowedContentTypes: [.pdf, .image]) { result in
            guard case .success(let url) = result else { return }
            Task { await read { try images(from: url) } }
        }
    }

    private func read(_ load: () async throws -> [CGImage]) async {
        isWorking = true
        message = nil
        defer { isWorking = false }
        do {
            let found = try await Timetable.read(try await load())
            lessons = found.sorted { ($0.weekday, $0.start) < ($1.weekday, $1.start) }
            if found.isEmpty { message = "No lessons found. Add them yourself below." }
        } catch {
            message = error.localizedDescription
        }
    }

    /// A PDF's first pages (rendered sharp enough to read), or an image file.
    private func images(from url: URL) throws -> [CGImage] {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        if let pdf = PDFDocument(url: url) {
            // ponytail: first 2 pages only; a timetable is rarely longer.
            return (0..<min(pdf.pageCount, 2)).compactMap { i in
                pdf.page(at: i).flatMap { $0.thumbnail(of: CGSize(width: 2000, height: 2000), for: .mediaBox).cgImage }
            }
        }
        guard let image = UIImage(contentsOfFile: url.path)?.cgImage else { throw TimetableError.unreadable }
        return [image]
    }

    private func add() async {
        let ready = lessons.filter { !$0.subject.trimmingCharacters(in: .whitespaces).isEmpty && $0.end > $0.start }
        do {
            try await Timetable.addToCalendar(ready, until: until)
            dismiss()
        } catch {
            message = error.localizedDescription
        }
    }

    private func minutes(_ value: Binding<Int>) -> Binding<Date> {
        Binding(
            get: { Calendar.current.startOfDay(for: .now).addingTimeInterval(TimeInterval(value.wrappedValue * 60)) },
            set: {
                let c = Calendar.current.dateComponents([.hour, .minute], from: $0)
                value.wrappedValue = (c.hour ?? 0) * 60 + (c.minute ?? 0)
            })
    }
}

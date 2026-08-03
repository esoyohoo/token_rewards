//
//  ContentView.swift
//  token-rewards
//
//  Created by RockPanda on 7/14/26.
//

import SwiftUI
import SwiftData
import PhotosUI
import UniformTypeIdentifiers

// MARK: - Models
enum CalendarScope: String, CaseIterable, Identifiable {
    case week = "Week"
    case month = "Month"
    var id: String { rawValue }
}

enum Mood: String, CaseIterable, Identifiable, Codable {
    case smile
    case neutral
    case sad
    var id: String { rawValue }

    var tokenDelta: Int {
        switch self {
        case .smile: return 1
        case .neutral: return 0
        case .sad: return -1
        }
    }

    var color: Color {
        switch self {
        case .smile: return .green
        case .neutral: return .yellow
        case .sad: return .red
        }
    }

    var systemName: String {
        switch self {
        case .smile: return "face.smiling"
        case .neutral: return "sun.max"
        case .sad: return "face.dashed"
        }
    }
}

@Model
final class DayEntry {
    @Attribute(.unique) var id: UUID
    var date: Date
    var moodRaw: String?
    var note: String

    var mood: Mood? {
        get { moodRaw.flatMap { Mood(rawValue: $0) } }
        set { moodRaw = newValue?.rawValue }
    }

    init(id: UUID = UUID(), date: Date, mood: Mood? = nil, note: String = "") {
        self.id = id
        self.date = dayOnly(date)
        self.moodRaw = mood?.rawValue
        self.note = note
    }
}

@Model
final class ProfileEntity {
    @Attribute(.unique) var id: UUID
    var name: String
    var emoji: String
    var sortOrder: Int
    var imageData: Data?
    @Relationship(deleteRule: .cascade) var entries: [DayEntry]

    init(id: UUID = UUID(), name: String, emoji: String, imageData: Data? = nil, sortOrder: Int = 0) {
        self.id = id
        self.name = name
        self.emoji = emoji
        self.imageData = imageData
        self.sortOrder = sortOrder
        self.entries = []
    }
}

// MARK: - ContentView
struct ContentView: View {
    init() {}

    @State private var scope: CalendarScope = .week
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\ProfileEntity.sortOrder, order: .forward), SortDescriptor(\ProfileEntity.name, order: .forward)]) private var profiles: [ProfileEntity]
    @State private var selectedProfileIDs: Set<UUID> = []
    @State private var showingAddSheet = false
    @State private var showingRemoveConfirm = false
    @State private var removeConfirmStep = 0
    @State private var removeErrorMessage: String? = nil
    @State private var showingOverview = false
    @State private var anchorDate: Date = Date()
    @State private var editingProfileID: UUID? = nil
    @State private var isEditing: Bool = false
    // Removed: @State private var showingProfilesEditSheet = false

    @AppStorage("didCleanupSeededProfiles") private var didCleanupSeededProfiles: Bool = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Pinned Previous/Next bar
                HStack(spacing: 0) {
                    Button {
                        shiftAnchor(by: -1)
                    } label: {
                        Text("Previous")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        shiftAnchor(by: 1)
                    } label: {
                        Text("Next")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(.horizontal)
                .padding(.top, 8)
                .padding(.bottom, 8)
                .background(.ultraThinMaterial)

                // Scrollable content below
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if !selectedProfiles.isEmpty {
                            ForEach(selectedProfiles) { profile in
                                ProfileSection(profile: binding(for: profile), scope: scope, anchorDate: anchorDate, isEditing: isEditing, onImageChange: { data in
                                    profiles.first { $0.id == profile.id }?.imageData = data
                                    try? modelContext.save()
                                })
                            }
                        } else {
                            VStack(spacing: 12) {
                                if profiles.isEmpty {
                                    Text("No profiles yet.")
                                        .foregroundStyle(.secondary)
                                    Button {
                                        showingAddSheet = true
                                    } label: {
                                        Label("Add your first profile", systemImage: "plus.circle.fill")
                                    }
                                    .buttonStyle(.borderedProminent)
                                } else {
                                    Text("Select users from the group menu to display.")
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.top, 40)
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("")
            .toolbar(content: {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Picker("Calendar View", selection: $scope) {
                            ForEach(CalendarScope.allCases) { s in
                                Text(s.rawValue).tag(s)
                            }
                        }
                    } label: {
                        Image(systemName: "calendar")
                    }
                }

                ToolbarItemGroup(placement: .topBarTrailing) {
                    if profiles.isEmpty {
                        // First-time use: show only a clear Add button
                        Button {
                            showingAddSheet = true
                        } label: {
                            Image(systemName: "plus")
                        }
                        .accessibilityLabel("Add profile")
                    } else {
                        // Existing users: show full toolbar options
                        Menu {
                            Section("Select users to display (up to 20)") {
                                ForEach(profiles) { profile in
                                    let isSelected = selectedProfileIDs.contains(profile.id)
                                    Button {
                                        toggleProfileSelection(profile.id)
                                    } label: {
                                        Label("\(profile.emoji) \(profile.name)", systemImage: isSelected ? "checkmark.circle.fill" : "circle")
                                    }
                                    .disabled(!isSelected && selectedProfileIDs.count >= 20)
                                }
                            }
                        } label: {
                            Image(systemName: "person.2")
                        }

                        Button("Overview") { showingOverview = true }

                        Menu("Edit") {
                            Button("Add") { showingAddSheet = true }
                            Button("Remove") { beginRemoveFlow() }
                        }
                    }
                }
            })
            .sheet(isPresented: $showingAddSheet) {
                AddProfileSheet { name, emoji in
                    addProfile(name: name, emoji: emoji)
                }
                .presentationDetents([.medium])
            }
            .alert("Please confirm", isPresented: $showingRemoveConfirm) {
                if removeConfirmStep == 0 {
                    Button("Yes") { handleRemoveYes() }
                    Button("No", role: .cancel) { cancelRemoveFlow() }
                } else {
                    Button("Yes") { handleRemoveYes() }
                    Button("No", role: .cancel) { cancelRemoveFlow() }
                }
            } message: {
                Text(removeErrorMessage ?? (removeConfirmStep == 0 ? "Step 1: Select Yes to continue." : "Step 2: Select Yes again to confirm deletion."))
            }
            .sheet(isPresented: $showingOverview) {
                OverviewView(profiles: profiles)
                    .presentationDetents([.medium, .large])
            }
            // Removed .sheet(isPresented: $showingProfilesEditSheet) {...}
            .onAppear {
                seedIfNeeded()
                cleanupSeededProfilesIfNeeded()
            }
        }
    }

    private var selectedProfiles: [ProfileEntity] {
        profiles.filter { selectedProfileIDs.contains($0.id) }
    }

    private func binding(for profile: ProfileEntity) -> Binding<ProfileEntity> {
        guard let index = profiles.firstIndex(where: { $0.id == profile.id }) else { fatalError("Profile not found") }
        return Binding(get: { profiles[index] }, set: { newValue in
            profiles[index].name = newValue.name
            profiles[index].emoji = newValue.emoji
            profiles[index].imageData = newValue.imageData
        })
    }

    private func toggleProfileSelection(_ id: UUID) {
        if selectedProfileIDs.contains(id) {
            selectedProfileIDs.remove(id)
        } else if selectedProfileIDs.count < 20 {
            selectedProfileIDs.insert(id)
        }
    }

    private func addProfile(name: String, emoji: String) {
        let new = ProfileEntity(name: name, emoji: emoji)
        new.sortOrder = (profiles.map { $0.sortOrder }.max() ?? -1) + 1
        modelContext.insert(new)
        try? modelContext.save()
        selectedProfileIDs.insert(new.id)
    }

    private func beginRemoveFlow() {
        removeConfirmStep = 0
        removeErrorMessage = nil
        showingRemoveConfirm = true
    }

    private func handleRemoveYes() {
        if removeConfirmStep == 0 {
            removeConfirmStep = 1
            removeErrorMessage = nil
            showingRemoveConfirm = true
        } else {
            if selectedProfileIDs.isEmpty {
                removeErrorMessage = "please select Yes"
                removeConfirmStep = 0
                showingRemoveConfirm = true
                return
            }
            for p in profiles where selectedProfileIDs.contains(p.id) {
                modelContext.delete(p)
            }
            try? modelContext.save()
            selectedProfileIDs.removeAll()
            showingRemoveConfirm = false
        }
    }

    private func cancelRemoveFlow() {
        removeErrorMessage = "please select Yes"
        showingRemoveConfirm = true
    }

    private func shiftAnchor(by delta: Int) {
        let comp: Calendar.Component = (scope == .week) ? .weekOfYear : .month
        if let newDate = Calendar.current.date(byAdding: comp, value: delta, to: anchorDate) {
            anchorDate = newDate
        }
    }

    private func seedIfNeeded() {
        // Intentionally left empty to prevent auto-seeding demo profiles
    }
    
    private func cleanupSeededProfilesIfNeeded() {
        guard !didCleanupSeededProfiles else { return }
        let seededNames: Set<String> = ["User 1", "User 2"]
        var didDeleteAny = false
        for p in profiles where seededNames.contains(p.name) {
            modelContext.delete(p)
            didDeleteAny = true
        }
        if didDeleteAny {
            try? modelContext.save()
        }
        didCleanupSeededProfiles = true
    }
}

// MARK: - Profile Section
struct ProfileSection: View {
    @Binding var profile: ProfileEntity
    var scope: CalendarScope
    var anchorDate: Date
    var isEditing: Bool
    var onImageChange: (Data?) -> Void

    @State private var selectedDate: Date = dayOnly(Date())
    @State private var photoSelection: PhotosPickerItem? = nil
    @State private var showCamera = false
    @State private var showDocumentPicker = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Group {
                    if let data = profile.imageData, let uiImage = UIImage(data: data) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 40, height: 40)
                            .clipShape(Circle())
                    } else {
                        Text(profile.emoji).font(.largeTitle)
                            .frame(width: 40, height: 40)
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    if isEditing {
                        Menu {
                            PhotosPicker("Choose from Library", selection: $photoSelection, matching: .images)
                            Button("Take Photo") { showCamera = true }
                                .disabled(!UIImagePickerController.isSourceTypeAvailable(.camera))
                            Button("Choose from Files") { showDocumentPicker = true }
                            if profile.imageData != nil { Button("Remove Photo", role: .destructive) { onImageChange(nil) } }
                        } label: {
                            Image(systemName: "camera.fill")
                                .font(.caption)
                                .padding(4)
                                .background(.thinMaterial, in: Circle())
                        }
                    }
                }

                if isEditing {
                    TextField("Name", text: Binding(
                        get: { profile.name },
                        set: { new in profile.name = new }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text(profile.name).font(.headline)
                }
                Spacer()
            }
            Text(formattedMDY(selectedDate))
                .font(.caption)
                .foregroundStyle(.secondary)

            CalendarGrid(scope: scope, anchorDate: anchorDate, selectedDate: $selectedDate, getMood: { date in
                entry(for: date)?.mood
            }, setMood: { date, newMood in
                let d = dayOnly(date)
                if let e = entry(for: d) {
                    e.mood = newMood
                } else {
                    let e = DayEntry(date: d, mood: newMood, note: "")
                    profile.entries.append(e)
                }
            })

            VStack(alignment: .leading) {
                Text("Note for selected day")
                    .font(.subheadline)
                TextField("Add a note...", text: Binding(
                    get: { entry(for: selectedDate)?.note ?? "" },
                    set: { text in
                        let d = dayOnly(selectedDate)
                        if let e = entry(for: d) {
                            e.note = text
                        } else {
                            let e = DayEntry(date: d, mood: nil, note: text)
                            profile.entries.append(e)
                        }
                    }
                ))
                .textFieldStyle(.roundedBorder)
            }

            let totals = TokenTotals(profile: profile, anchorDate: anchorDate)
            VStack(alignment: .leading, spacing: 4) {
                Text("Weekly total: \(totals.week)")
                Text("Monthly total: \(totals.month)")
                Text("Year total: \(totals.year)")
                Text("YTD total: \(totals.ytd)")
            }
            .font(.footnote)
            .padding(.top, 4)
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .onChange(of: photoSelection) { _, _ in
            Task { await loadSelectedPhoto() }
        }
        .sheet(isPresented: $showCamera) {
            CameraImagePicker(sourceType: .camera) { image in
                if let data = image.jpegData(compressionQuality: 0.9) {
                    onImageChange(data)
                }
            }
        }
        .sheet(isPresented: $showDocumentPicker) {
            DocumentPicker(allowedContentTypes: [UTType.image]) { url in
                if let url, let data = try? Data(contentsOf: url) {
                    onImageChange(data)
                }
            }
        }
    }

    private func entry(for date: Date) -> DayEntry? {
        let d = dayOnly(date)
        return profile.entries.first { dayOnly($0.date) == d }
    }
}

extension ProfileSection {
    func loadSelectedPhoto() async {
        guard let item = photoSelection else { return }
        if let data = try? await item.loadTransferable(type: Data.self) {
            await MainActor.run { onImageChange(data) }
        }
    }
}

// MARK: - Calendar Grid
struct CalendarGrid: View {
    var scope: CalendarScope
    var anchorDate: Date
    @Binding var selectedDate: Date
    var getMood: (Date) -> Mood?
    var setMood: (Date, Mood?) -> Void

    private var cal: Calendar { Calendar.current }
    private var weekdaySymbols: [String] {
        let symbols = cal.veryShortStandaloneWeekdaySymbols
        let first = cal.firstWeekday - 1 // convert to 0-based index
        return Array(symbols[first...] + symbols[..<first])
    }

    private func leadingBlankCount(for monthStart: Date) -> Int {
        // Number of empty cells before the first day of month to align with firstWeekday
        let weekday = cal.component(.weekday, from: monthStart) // 1=Sunday... by default
        let first = cal.firstWeekday // 1-based
        // Normalize to 0-based and compute offset
        let offset = (weekday - first + 7) % 7
        return offset
    }

    private func weeksForMonth(_ anchorDate: Date) -> [[Date?]] {
        // Build a matrix of weeks for the month: [[Date?]] including nils for blanks
        guard let interval = cal.dateInterval(of: .month, for: anchorDate) else { return [] }
        let days = stride(from: interval.start, to: interval.end, by: 24*60*60).map { $0 }
        let blanks = leadingBlankCount(for: interval.start)
        let padded: [Date?] = Array(repeating: nil, count: blanks) + days.map { Optional($0) }
        var weeks: [[Date?]] = []
        var current: [Date?] = []
        for cell in padded {
            current.append(cell)
            if current.count == 7 {
                weeks.append(current)
                current.removeAll(keepingCapacity: true)
            }
        }
        if !current.isEmpty { // pad last week to 7
            current.append(contentsOf: Array(repeating: nil, count: 7 - current.count))
            weeks.append(current)
        }
        return weeks
    }

    var body: some View {
        switch scope {
        case .month:
            let weeks = weeksForMonth(anchorDate)
            VStack(spacing: 8) {
                // Weekday headers
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 7), spacing: 8) {
                    ForEach(weekdaySymbols, id: \.self) { sym in
                        Text(sym.uppercased())
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                    }
                }
                // Weeks rows
                ForEach(0..<weeks.count, id: \.self) { w in
                    let row = weeks[w]
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 7), spacing: 8) {
                        ForEach(0..<7, id: \.self) { i in
                            if let day = row[i] {
                                DayCell(date: day,
                                        isSelected: dayOnly(day) == dayOnly(selectedDate),
                                        mood: getMood(day),
                                        onSelect: { selectedDate = dayOnly(day) },
                                        onSetMood: { setMood(day, $0) })
                            } else {
                                // Blank cell to preserve alignment
                                Color.clear
                                    .frame(height: 48)
                            }
                        }
                    }
                }
            }
        case .week:
            let days = daysForScope(scope, anchorDate)
            VStack(spacing: 8) {
                // Weekday headers for the week view
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 7), spacing: 8) {
                    ForEach(weekdaySymbols, id: \.self) { sym in
                        Text(sym.uppercased())
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                    }
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 7), spacing: 8) {
                    ForEach(days, id: \.self) { day in
                        DayCell(date: day,
                                isSelected: dayOnly(day) == dayOnly(selectedDate),
                                mood: getMood(day),
                                onSelect: { selectedDate = dayOnly(day) },
                                onSetMood: { setMood(day, $0) })
                    }
                }
            }
        }
    }
}

struct DayCell: View {
    let date: Date
    let isSelected: Bool
    let mood: Mood?
    let onSelect: () -> Void
    let onSetMood: (Mood?) -> Void

    var body: some View {
        VStack(spacing: 6) {
            Text(dayNumber(date))
                .font(.caption2)
                .foregroundStyle(.secondary)
            Menu {
                ForEach(Mood.allCases) { m in
                    Button { onSetMood(m) } label: {
                        Label(m.rawValue.capitalized, systemImage: m.systemName)
                            .foregroundStyle(m.color)
                    }
                }
                if mood != nil {
                    Button(role: .destructive) { onSetMood(nil) } label: { Label("Clear", systemImage: "xmark.circle") }
                }
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill((mood?.color ?? Color.gray.opacity(0.2)))
                        .frame(height: 36)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
                        )
                    if let mood {
                        Image(systemName: mood.systemName).foregroundStyle(.white)
                    } else {
                        Image(systemName: "face.smiling").opacity(0.2)
                    }
                }
            }
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.gray.opacity(0.2))
        )
        .onTapGesture { onSelect() }
    }
}

// MARK: - Totals
struct TokenTotals {
    let week: Int
    let month: Int
    let year: Int
    let ytd: Int

    init(profile: ProfileEntity, anchorDate: Date) {
        let cal = Calendar.current
        let yearOfToday = cal.component(.year, from: anchorDate)

        func sum(in range: Range<Date>) -> Int {
            profile.entries.reduce(0) { partial, e in
                let day = dayOnly(e.date)
                if range.contains(day), let mood = e.mood {
                    return partial + mood.tokenDelta
                }
                return partial
            }
        }

        let weekRange = cal.dateInterval(of: .weekOfYear, for: anchorDate)!
        let monthRange = cal.dateInterval(of: .month, for: anchorDate)!
        let yearRange = cal.dateInterval(of: .year, for: anchorDate)!
        let ytdStart = cal.date(from: DateComponents(year: yearOfToday, month: 1, day: 1))!
        let ytdRange = ytdStart..<anchorDate.addingTimeInterval(24*60*60)

        self.week = sum(in: weekRange.start..<weekRange.end)
        self.month = sum(in: monthRange.start..<monthRange.end)
        self.year = sum(in: yearRange.start..<yearRange.end)
        self.ytd = sum(in: ytdRange)
    }
}

// MARK: - Helpers
func daysForScope(_ scope: CalendarScope, _ anchorDate: Date) -> [Date] {
    let cal = Calendar.current
    switch scope {
    case .week:
        let interval = cal.dateInterval(of: .weekOfYear, for: anchorDate)!
        return stride(from: interval.start, to: interval.end, by: 24*60*60).map { $0 }
    case .month:
        let interval = cal.dateInterval(of: .month, for: anchorDate)!
        return stride(from: interval.start, to: interval.end, by: 24*60*60).map { $0 }
    }
}

func dayOnly(_ date: Date) -> Date {
    let cal = Calendar.current
    return cal.startOfDay(for: date)
}

func dayNumber(_ date: Date) -> String {
    let cal = Calendar.current
    let d = cal.component(.day, from: date)
    return String(d)
}

func formattedMDY(_ date: Date) -> String {
    let f = DateFormatter()
    f.calendar = Calendar.current
    f.dateFormat = "MM/dd/yyyy"
    return f.string(from: date)
}

// MARK: - Add Profile Sheet
struct AddProfileSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name: String = ""
    @State private var selectedEmoji: String = "🙂"

    let onAdd: (String, String) -> Void

    // Simple emoji palette to simulate choosing from iOS emoji
    private let emojiOptions: [String] = ["🙂","😀","😎","🤓","🥳","🧒","👦","👧","🧑","👩","👨","🧔","👩‍🦰","👩‍🦱","👩‍🦳","👨‍🦰","👨‍🦱","👨‍🦳","👶","🧓"]

    var body: some View {
        NavigationStack {
            Form {
                Section("Profile Name") {
                    TextField("Name", text: $name)
                }
                Section("Choose an emoji") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(emojiOptions, id: \.self) { emoji in
                                Text(emoji)
                                    .font(.largeTitle)
                                    .padding(6)
                                    .background(selectedEmoji == emoji ? Color.blue.opacity(0.2) : Color.clear)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                    .onTapGesture { selectedEmoji = emoji }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle("Add Profile")
            .toolbar(content: {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                        onAdd(name, selectedEmoji)
                        dismiss()
                    }
                }
            })
        }
    }
}

// MARK: - Edit Profile Sheet
struct EditProfileSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var pickedImageData: Data?

    @State private var showCamera = false
    @State private var showDocumentPicker = false

    let profile: ProfileEntity
    let onSave: (String, Data?) -> Void

    init(profile: ProfileEntity, onSave: @escaping (String, Data?) -> Void) {
        self.profile = profile
        self.onSave = onSave
        _name = State(initialValue: profile.name)
        _pickedImageData = State(initialValue: profile.imageData)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Profile Name") {
                    TextField("Name", text: $name)
                }
                Section("Photo") {
                    VStack(spacing: 12) {
                        if let data = pickedImageData, let ui = UIImage(data: data) {
                            Image(uiImage: ui)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 80, height: 80)
                                .clipShape(Circle())
                        } else {
                            ZStack {
                                Circle().fill(Color.gray.opacity(0.2)).frame(width: 80, height: 80)
                                Image(systemName: "person.crop.circle").font(.largeTitle).foregroundStyle(.secondary)
                            }
                        }
                        PhotosPicker("Choose from Library", selection: $photoSelection, matching: .images)
                        Button("Take Photo") { showCamera = true }
                            .disabled(!UIImagePickerController.isSourceTypeAvailable(.camera))
                        Button("Choose from Files") { showDocumentPicker = true }
                        Button("Remove Photo", role: .destructive) { pickedImageData = nil }
                            .disabled(pickedImageData == nil)
                    }
                }
            }
            .navigationTitle("Edit Profile")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(name, pickedImageData)
                        dismiss()
                    }
                }
            }
            .task {
                await loadSelectedPhoto()
            }
            .onChange(of: photoSelection) { _, _ in
                Task { await loadSelectedPhoto() }
            }
            .sheet(isPresented: $showCamera) {
                CameraImagePicker(sourceType: .camera) { image in
                    if let data = image.jpegData(compressionQuality: 0.9) {
                        pickedImageData = data
                    }
                }
            }
            .sheet(isPresented: $showDocumentPicker) {
                DocumentPicker(allowedContentTypes: [UTType.image]) { url in
                    if let url, let data = try? Data(contentsOf: url) {
                        pickedImageData = data
                    }
                }
            }
        }
    }

    // MARK: PhotosPicker
    @State private var photoSelection: PhotosPickerItem? = nil
}

extension EditProfileSheet {
    func loadSelectedPhoto() async {
        guard let item = photoSelection else { return }
        if let data = try? await item.loadTransferable(type: Data.self) {
            await MainActor.run { pickedImageData = data }
        }
    }
}

// MARK: - UIKit Wrappers for Camera and Document Picker

struct CameraImagePicker: UIViewControllerRepresentable {
    enum SourceType {
        case camera
        case photoLibrary

        var uiType: UIImagePickerController.SourceType {
            switch self {
            case .camera: return .camera
            case .photoLibrary: return .photoLibrary
            }
        }
    }

    var sourceType: SourceType
    var onImagePicked: (UIImage) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = sourceType.uiType
        picker.delegate = context.coordinator
        picker.allowsEditing = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let parent: CameraImagePicker
        init(_ parent: CameraImagePicker) { self.parent = parent }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.onImagePicked(image)
            }
            picker.dismiss(animated: true)
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
        }
    }
}

struct DocumentPicker: UIViewControllerRepresentable {
    var allowedContentTypes: [UTType]
    var onPick: (URL?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let controller = UIDocumentPickerViewController(forOpeningContentTypes: allowedContentTypes, asCopy: true)
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let parent: DocumentPicker
        init(_ parent: DocumentPicker) { self.parent = parent }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            parent.onPick(urls.first)
        }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            parent.onPick(nil)
        }
    }
}

// MARK: - Overview Placeholder
struct OverviewView: View {
    let profiles: [ProfileEntity]
    var body: some View {
        NavigationStack {
            List(profiles) { p in
                HStack {
                    Text(p.emoji)
                    Text(p.name)
                    Spacer()
                    let totals = TokenTotals(profile: p, anchorDate: Date())
                    Text("W: \(totals.week) M: \(totals.month) Y: \(totals.year)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Overview")
        }
    }
}

#Preview {
    ContentView()
}

import SwiftUI

private let classColors = [
    "#4285F4", "#EA4335", "#FBBC04", "#34A853",
    "#FF6D01", "#46BDC6", "#7BAAF7", "#F07B72",
    "#A142F4", "#24C1E0", "#F538A0", "#185ABC"
]

private let dayNames = [0: "Sun", 1: "Mon", 2: "Tue", 3: "Wed", 4: "Thu", 5: "Fri", 6: "Sat"]

// MARK: - Main View

struct ManageClassesView: View {
    @Environment(CanopyStore.self) private var store
    @State private var editingClass: SchoolClass?
    @State private var showAdd = false
    @State private var deleteTarget: SchoolClass?
    @State private var showDeleteConfirm = false
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            CanopyBackground()
            if store.classes.isEmpty {
                emptyState
            } else {
                classList
            }
        }
        .navigationTitle("Classes")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showAdd = true } label: {
                    Image(systemName: "plus.circle.fill").font(.title3)
                }
            }
        }
        .sheet(isPresented: $showAdd) {
            ClassEditorSheet(cls: nil).presentationDetents([.large])
        }
        .sheet(item: $editingClass) { cls in
            ClassEditorSheet(cls: cls).presentationDetents([.large])
        }
        .alert("Delete Class?", isPresented: $showDeleteConfirm, presenting: deleteTarget) { cls in
            Button("Delete", role: .destructive) {
                Task { await store.deleteClass(cls) }
            }
            Button("Cancel", role: .cancel) { }
        } message: { cls in
            Text("Remove \"\(cls.name)\" permanently? This cannot be undone.")
        }
        .refreshable { await store.loadAll() }
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "No Classes",
            systemImage: "books.vertical",
            description: Text("Add your first class to get started.")
        )
    }

    private var classList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(store.classes.sorted { $0.period < $1.period }) { cls in
                    Button { editingClass = cls } label: {
                        ClassCard(cls: cls)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button { editingClass = cls } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        Button(role: .destructive) {
                            deleteTarget = cls
                            showDeleteConfirm = true
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
            .padding(16)
            .padding(.bottom, 32)
        }
    }
}

// MARK: - Class Card

struct ClassCard: View {
    let cls: SchoolClass

    var body: some View {
        VStack(spacing: 0) {
            // Color strip
            Color(hex: cls.color)
                .frame(height: 5)
                .clipShape(UnevenRoundedRectangle(
                    topLeadingRadius: 14, bottomLeadingRadius: 0,
                    bottomTrailingRadius: 0, topTrailingRadius: 14
                ))

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(cls.name)
                        .font(.headline)
                        .foregroundStyle(Color(hex: cls.color))
                    Spacer()
                    Text("Period \(cls.period)")
                        .font(.caption.bold())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color(hex: cls.color).opacity(0.12), in: Capsule())
                        .foregroundStyle(Color(hex: cls.color))
                }

                VStack(alignment: .leading, spacing: 4) {
                    if !cls.teacher.isEmpty {
                        Label(cls.teacher, systemImage: "person")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    if !cls.room.isEmpty {
                        Label("Room \(cls.room)", systemImage: "door.right.hand.open")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Label("\(cls.startTime) – \(cls.endTime)", systemImage: "clock")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 4) {
                    ForEach(cls.days.sorted(), id: \.self) { d in
                        Text(dayNames[d] ?? "?")
                            .font(.caption2.bold())
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Color(hex: cls.color).opacity(0.10), in: Capsule())
                            .foregroundStyle(Color(hex: cls.color))
                            .overlay(Capsule().strokeBorder(Color(hex: cls.color).opacity(0.3), lineWidth: 0.5))
                    }

                    Spacer()

                    if !cls.semester.isEmpty {
                        Text(cls.semester)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .padding(14)
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(Color.secondary.opacity(0.2), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.05), radius: 6, y: 2)
    }
}

// MARK: - Class Editor Sheet

struct ClassEditorSheet: View {
    @Environment(CanopyStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let cls: SchoolClass?
    private var isNew: Bool { cls == nil }

    @State private var name = ""
    @State private var teacher = ""
    @State private var room = ""
    @State private var period = 1
    @State private var startTime = "08:00"
    @State private var endTime = "08:50"
    @State private var semester = "Spring 2026"
    @State private var selectedDays: Set<Int> = [1, 2, 3, 4, 5]
    @State private var selectedColor = "#4285F4"
    @State private var isSaving = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            ZStack { CanopyBackground()
                ScrollView {
                    VStack(spacing: 16) {
                        // Name, Teacher, Room
                        FormEditCard {
                            VStack(spacing: 0) {
                                TextField("Class Name", text: $name)
                                    .font(.body)
                                    .padding(.horizontal, 16).padding(.vertical, 13)
                                Divider().padding(.leading, 16)
                                TextField("Teacher", text: $teacher)
                                    .font(.body)
                                    .padding(.horizontal, 16).padding(.vertical, 13)
                                Divider().padding(.leading, 16)
                                TextField("Room", text: $room)
                                    .font(.body)
                                    .padding(.horizontal, 16).padding(.vertical, 13)
                            }
                        }

                        // Period and Time
                        FormEditCard {
                            VStack(spacing: 0) {
                                HStack {
                                    Label("Period", systemImage: "number").font(.body)
                                    Spacer()
                                    Stepper("\(period)", value: $period, in: 1...10)
                                        .fixedSize()
                                }
                                .padding(.horizontal, 16).padding(.vertical, 13)
                                Divider().padding(.leading, 16)
                                HStack {
                                    Label("Start", systemImage: "clock").font(.body)
                                    Spacer()
                                    TimeInputField(time: $startTime)
                                }
                                .padding(.horizontal, 16).padding(.vertical, 10)
                                Divider().padding(.leading, 16)
                                HStack {
                                    Label("End", systemImage: "clock.badge.checkmark").font(.body)
                                    Spacer()
                                    TimeInputField(time: $endTime)
                                }
                                .padding(.horizontal, 16).padding(.vertical, 10)
                            }
                        }

                        // Semester
                        FormEditCard {
                            HStack {
                                Label("Semester", systemImage: "calendar").font(.body)
                                Spacer()
                                TextField("e.g. Spring 2026", text: $semester)
                                    .multilineTextAlignment(.trailing)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 16).padding(.vertical, 13)
                        }

                        // Days
                        FormEditCard {
                            VStack(alignment: .leading, spacing: 10) {
                                Label("Days", systemImage: "calendar.day.timeline.left")
                                    .font(.body)
                                    .padding(.horizontal, 16).padding(.top, 13)
                                HStack(spacing: 6) {
                                    ForEach([1,2,3,4,5,6,0], id: \.self) { day in
                                        let label = dayNames[day] ?? "?"
                                        let selected = selectedDays.contains(day)
                                        Button {
                                            withAnimation(.spring(response: 0.2)) {
                                                if selected { selectedDays.remove(day) }
                                                else { selectedDays.insert(day) }
                                            }
                                        } label: {
                                            Text(label)
                                                .font(.caption.bold())
                                                .frame(maxWidth: .infinity)
                                                .padding(.vertical, 8)
                                                .background(
                                                    selected ? Color.accentColor.opacity(0.15) : Color.clear,
                                                    in: RoundedRectangle(cornerRadius: 8)
                                                )
                                                .overlay(RoundedRectangle(cornerRadius: 8)
                                                    .strokeBorder(selected ? Color.accentColor.opacity(0.6) : Color.secondary.opacity(0.25), lineWidth: 1))
                                                .foregroundStyle(selected ? Color.accentColor : .secondary)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.horizontal, 12).padding(.bottom, 12)
                            }
                        }

                        // Color
                        FormEditCard {
                            VStack(alignment: .leading, spacing: 10) {
                                Label("Color", systemImage: "paintpalette")
                                    .font(.body)
                                    .padding(.horizontal, 16).padding(.top, 13)
                                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 10) {
                                    ForEach(classColors, id: \.self) { hex in
                                        Button {
                                            withAnimation(.spring(response: 0.2)) { selectedColor = hex }
                                        } label: {
                                            Circle()
                                                .fill(Color(hex: hex))
                                                .frame(width: 32, height: 32)
                                                .overlay(
                                                    Circle().strokeBorder(
                                                        selectedColor == hex ? Color.primary : Color.clear,
                                                        lineWidth: 2.5
                                                    )
                                                    .padding(-3)
                                                )
                                                .overlay(
                                                    Image(systemName: "checkmark")
                                                        .font(.caption.weight(.bold))
                                                        .foregroundStyle(.white)
                                                        .opacity(selectedColor == hex ? 1 : 0)
                                                )
                                        }
                                        .buttonStyle(.plain)
                                        .scaleEffect(selectedColor == hex ? 1.12 : 1)
                                        .animation(.spring(response: 0.2), value: selectedColor)
                                    }
                                }
                                .padding(.horizontal, 16).padding(.bottom, 14)
                            }
                        }

                        if let e = error {
                            HStack(spacing: 8) {
                                Image(systemName: "exclamationmark.triangle.fill").font(.footnote)
                                Text(e).font(.footnote)
                            }
                            .foregroundStyle(.red)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                        }
                    }
                    .padding(16).padding(.bottom, 32)
                }
            }
            .navigationTitle(isNew ? "New Class" : "Edit Class")
            .navigationBarTitleInline()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving…" : "Save") { Task { await save() } }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                        .fontWeight(.semibold)
                }
            }
        }
        .onAppear { prefill() }
    }

    private func prefill() {
        guard let cls else { return }
        name = cls.name
        teacher = cls.teacher
        room = cls.room
        period = cls.period
        startTime = cls.startTime
        endTime = cls.endTime
        semester = cls.semester
        selectedDays = Set(cls.days)
        selectedColor = cls.color
    }

    private func save() async {
        isSaving = true; defer { isSaving = false }
        let item = SchoolClass(
            id: cls?.id ?? UUID().uuidString,
            name: name.trimmingCharacters(in: .whitespaces),
            teacher: teacher,
            room: room,
            color: selectedColor,
            period: period,
            startTime: startTime,
            endTime: endTime,
            days: Array(selectedDays).sorted(),
            dayTimes: cls?.dayTimes,
            semester: semester,
            source: cls?.source,
            grade: cls?.grade,
            gradePercent: cls?.gradePercent
        )
        do {
            try await store.saveClass(item, isNew: isNew)
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}

// MARK: - Time Input Helper

struct TimeInputField: View {
    @Binding var time: String

    // Parse time string into hours/minutes
    private var components: (Int, Int) {
        let parts = time.split(separator: ":").compactMap { Int($0) }
        return (parts.first ?? 8, parts.last ?? 0)
    }

    var body: some View {
        let (hours, minutes) = components
        HStack(spacing: 2) {
            Picker("Hour", selection: Binding(
                get: { hours },
                set: { newH in time = String(format: "%02d:%02d", newH, minutes) }
            )) {
                ForEach(0...23, id: \.self) { h in
                    Text(String(format: "%02d", h)).tag(h)
                }
            }
            .wheelPickerStyle()
            #if !os(macOS)
            .frame(width: 55, height: 80)
            .clipped()
            #endif

            Text(":").font(.title3.bold()).foregroundStyle(.secondary)

            Picker("Minute", selection: Binding(
                get: { minutes },
                set: { newM in time = String(format: "%02d:%02d", hours, newM) }
            )) {
                ForEach([0, 5, 10, 15, 20, 25, 30, 35, 40, 45, 50, 55], id: \.self) { m in
                    Text(String(format: "%02d", m)).tag(m)
                }
            }
            .wheelPickerStyle()
            #if !os(macOS)
            .frame(width: 55, height: 80)
            .clipped()
            #endif
        }
    }
}

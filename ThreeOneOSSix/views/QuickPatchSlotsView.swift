import SwiftUI

/// Five independent shortcuts into the existing patch project library.
/// Each slot stores only a project ID and a display name; package data remains
/// in PatchProjectLibrary, so importing another package never replaces a slot's file.
private struct QuickPatchSlot: Codable, Identifiable {
    var id: Int
    var title: String
    var projectID: UUID?
    var isOn: Bool
}

struct QuickPatchSlotsView: View {
    @EnvironmentObject private var store: PatchProjectStore
    @State private var slots: [QuickPatchSlot] = Self.loadSlots()
    @State private var editingSlot: Int?
    @State private var editedName = ""
    @State private var workingSlot: Int?
    @State private var message: String?
    @State private var showImporter = false
    @State private var importingSlot: Int?
    @State private var previousProjectIDs = Set<UUID>()

    private static let storageKey = "vip.quickPatchSlots.v1"

    private static func loadSlots() -> [QuickPatchSlot] {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let saved = try? JSONDecoder().decode([QuickPatchSlot].self, from: data),
           saved.count == 5 {
            return saved
        }
        return (1...5).map {
            QuickPatchSlot(id: $0, title: "Patch \($0)", projectID: nil, isOn: false)
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(slots) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("QUICK PATCHES")
                    .font(.caption.weight(.bold))
                    .tracking(1.1)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("5 SLOTS")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            ForEach(slots.indices, id: \.self) { index in
                slotRow(index)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color(red: 0.075, green: 0.085, blue: 0.15))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.purple.opacity(0.32), lineWidth: 1)
        )
        .alert("Rename slot", isPresented: Binding(
            get: { editingSlot != nil },
            set: { if !$0 { editingSlot = nil } }
        )) {
            TextField("Slot name", text: $editedName)
            Button("Save") {
                if let index = editingSlot {
                    let trimmed = editedName.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty { slots[index].title = trimmed }
                    save()
                }
                editingSlot = nil
            }
            Button("Cancel", role: .cancel) { editingSlot = nil }
        }
        .alert("Quick Patch", isPresented: Binding(
            get: { message != nil },
            set: { if !$0 { message = nil } }
        )) {
            Button("OK", role: .cancel) { message = nil }
        } message: {
            Text(message ?? "")
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.data],
            allowsMultipleSelection: false
        ) { result in
            guard let index = importingSlot else { return }
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                previousProjectIDs = Set(store.items.map(\.id))
                store.importPackage(at: url)
                importingSlot = index
            case .failure(let error):
                message = error.localizedDescription
                importingSlot = nil
            }
        }
        .onChange(of: store.isBusy) { busy in
            guard !busy, let index = importingSlot else { return }
            store.reload()
            if let imported = store.items.first(where: { !previousProjectIDs.contains($0.id) && !$0.isLocked }) {
                slots[index].projectID = imported.id
                slots[index].isOn = false
                save()
            }
            importingSlot = nil
        }
    }

    @ViewBuilder
    private func slotRow(_ index: Int) -> some View {
        let slot = slots[index]
        let selected = store.items.first(where: { $0.id == slot.projectID })
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 7) {
                    Text(slot.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Button {
                        editedName = slot.title
                        editingSlot = index
                    } label: {
                        Image(systemName: "pencil")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.65))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Rename \(slot.title)")
                }

                Menu {
                    Button {
                        importingSlot = index
                        showImporter = true
                    } label: {
                        Label("Import project file…", systemImage: "square.and.arrow.down")
                    }
                    if store.items.isEmpty {
                        Text("Import a project using the + button first")
                    }
                    ForEach(store.items) { item in
                        Button {
                            guard !item.isLocked else {
                                message = "Unlock this project before assigning it to a slot."
                                return
                            }
                            slots[index].projectID = item.id
                            slots[index].isOn = false
                            save()
                        } label: {
                            Label(
                                item.project?.name ?? "Locked project",
                                systemImage: slots[index].projectID == item.id
                                    ? "checkmark.circle.fill" : "shippingbox"
                            )
                        }
                    }
                    if slot.projectID != nil {
                        Button("Remove project from slot", role: .destructive) {
                            slots[index].projectID = nil
                            slots[index].isOn = false
                            save()
                        }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "doc.badge.plus")
                        Text(selected?.project?.name ?? "Choose imported project")
                            .lineLimit(1)
                    }
                    .font(.caption)
                    .foregroundStyle(selected == nil ? .orange : .white.opacity(0.7))
                }
                .disabled(workingSlot == index)
            }

            Spacer(minLength: 4)

            if workingSlot == index {
                ProgressView().tint(.purple)
            } else {
                Toggle(slot.title, isOn: Binding(
                    get: { slots[index].isOn },
                    set: { newValue in setEnabled(newValue, at: index) }
                ))
                .labelsHidden()
                .tint(.green)
                .disabled(selected?.project == nil || store.isBusy)
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 12))
    }

    private func setEnabled(_ enabled: Bool, at index: Int) {
        guard workingSlot == nil,
              let projectID = slots[index].projectID,
              let item = store.items.first(where: { $0.id == projectID }),
              let project = item.project,
              !item.isLocked else {
            message = "Choose an unlocked project for this slot first."
            return
        }

        workingSlot = index
        Task.detached(priority: .userInitiated) {
            do {
                if enabled {
                    let currentProject = item.summary.schemaVersion >= 2 && item.canInspectContents
                        ? try PatchProjectLibrary.synchronizeWorkspace(item: item)
                        : project
                    _ = try DevicePatchService.apply(project: currentProject)
                } else {
                    guard let receipt = DevicePatchService.latestReceipt(projectID: projectID) else {
                        throw PatchPackageError.restoreFailed
                    }
                    let inspection = try DevicePatchService.inspectRestore(receipt: receipt)
                    guard inspection.changedTargets.isEmpty else {
                        throw PatchPackageError.restoreTargetsChanged(inspection.changedTargets.map(\.displayPath))
                    }
                    try DevicePatchService.restore(receipt: receipt)
                }
                await MainActor.run {
                    slots[index].isOn = enabled
                    save()
                    workingSlot = nil
                    store.reload()
                }
            } catch {
                await MainActor.run {
                    workingSlot = nil
                    slots[index].isOn = !enabled
                    message = error.localizedDescription
                }
            }
        }
    }
}

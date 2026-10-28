import AppKit
import SummonCore
import SwiftUI

/// Every update on this Mac, like the App Store's Updates page: Summon first, then Agents, Homebrew, bun & npm and
/// macOS. Each row installs on its own and shows its state; nothing opens a terminal unless a password is needed.
public struct UpdatesView: View {
    public static let windowID = "updates"
    public static let title = "Updates"

    @Bindable var model: SummonModel
    @State private var details: Set<String> = []
    @State private var wasAccessory = false

    public init(model: SummonModel) {
        self.model = model
    }

    private var commandUpdates: [SoftwareUpdate] { model.pendingUpdates.filter { $0.command != nil } }

    public var body: some View {
        Group {
            if model.updates.isEmpty {
                ContentUnavailableView {
                    Label(model.isCheckingUpdates ? "Checking for Updates…" : "Everything Is Up to Date",
                          systemImage: model.isCheckingUpdates ? "arrow.triangle.2.circlepath" : "checkmark.circle")
                } description: {
                    Text(model.updateStatus ?? checkedLine)
                }
            } else {
                Form {
                    if let summon = model.updates.first(where: { $0.source == .summon }) {
                        summonCard(summon)
                    }
                    ForEach(SoftwareUpdate.Group.allCases.filter { $0 != .summon }, id: \.self) { group in
                        let rows = model.updates.filter { $0.group == group }
                        if !rows.isEmpty { section(group, rows) }
                    }
                }
                .formStyle(.grouped)
            }
        }
        .frame(minWidth: 520, minHeight: 360)
        .toolbar {
            ToolbarItem(placement: .status) {
                Text(model.isCheckingUpdates ? "Checking…" : checkedLine)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            ToolbarItem {
                Button { Task { await model.checkForUpdates() } } label: {
                    Label("Check Now", systemImage: "arrow.clockwise")
                }
                .disabled(model.isCheckingUpdates)
                .help("Check for updates now")
            }
            ToolbarItem(placement: .primaryAction) {
                Button(commandUpdates.count > 1 ? "Update All (\(commandUpdates.count))" : "Update All") {
                    model.install(commandUpdates)
                }
                .disabled(commandUpdates.isEmpty)
            }
        }
        .onAppear {
            // An accessory app's window gets no Dock icon or ⌘Tab; become a regular app while it is open.
            wasAccessory = NSApp.activationPolicy() == .accessory
            if wasAccessory { NSApp.setActivationPolicy(.regular) }
            NSApp.activate()
            if model.lastUpdateCheck == nil { Task { await model.checkForUpdates() } }
        }
        .onDisappear {
            if wasAccessory { NSApp.setActivationPolicy(.accessory) }
        }
    }

    private var checkedLine: String {
        guard let checked = model.lastUpdateCheck else { return "Not checked yet" }
        return "Checked " + checked.formatted(.relative(presentation: .named))
    }

    /// Summon's own update, like an app's update sheet: the version, its notes, Install and Relaunch.
    private func summonCard(_ update: SoftwareUpdate) -> some View {
        Section {
            HStack(spacing: 12) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 44, height: 44)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Summon \(update.latest) is available").font(.headline)
                    Text("You have \(update.current). Summon relaunches and asks for Accessibility again.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if model.isUpdating {
                    ProgressView().controlSize(.small)
                } else {
                    if let link = update.link.flatMap(URL.init(string:)) {
                        Link("What's New", destination: link)
                    }
                    Button("Install and Relaunch") { model.update(update) }
                        .buttonStyle(.borderedProminent)
                }
            }
            if let status = model.updateStatus, model.isUpdating || status.hasPrefix("Update failed") {
                Text(status).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }

    private func section(_ group: SoftwareUpdate.Group, _ rows: [SoftwareUpdate]) -> some View {
        let installable = rows.filter { $0.command != nil && model.updateStates[$0.id] != .done }
        return Section {
            ForEach(rows) { update in row(update) }
        } header: {
            HStack {
                Label(group.title, systemImage: group.icon)
                Spacer()
                if installable.count > 1 {
                    Button("Update All") { model.install(installable) }
                        .buttonStyle(.link)
                        .font(.subheadline)
                }
            }
        }
    }

    @ViewBuilder private func row(_ update: SoftwareUpdate) -> some View {
        let state = model.updateStates[update.id]
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(update.name)
                    Text(update.current.isEmpty ? update.latest : "\(update.current) → \(update.latest)")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Spacer()
                stateView(update, state)
            }
            if case .failed(let output) = state, details.contains(update.id) {
                ScrollView {
                    Text(output.trimmingCharacters(in: .whitespacesAndNewlines))
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 140)
                .padding(8)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
            }
        }
        .contextMenu {
            if let link = update.link.flatMap(URL.init(string:)) {
                Button("What's New") { NSWorkspace.shared.open(link) }
            }
            Button("Skip This Version") { model.skip(update) }
        }
    }

    @ViewBuilder private func stateView(_ update: SoftwareUpdate, _ state: UpdateRowState?) -> some View {
        switch state {
        case .queued:
            Text("Waiting…").font(.subheadline).foregroundStyle(.secondary)
        case .running:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Updating…").font(.subheadline).foregroundStyle(.secondary)
            }
        case .done:
            Label("Updated", systemImage: "checkmark.circle.fill")
                .font(.subheadline)
                .foregroundStyle(.green)
        case .failed:
            HStack(spacing: 8) {
                Label(state?.needsTerminal == true ? "Needs your password" : "Failed", systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline)
                    .foregroundStyle(.orange)
                Button(details.contains(update.id) ? "Hide Details" : "Show Details") {
                    if details.contains(update.id) { details.remove(update.id) } else { details.insert(update.id) }
                }
                .buttonStyle(.link)
                .font(.subheadline)
                if state?.needsTerminal == true {
                    Button("Open in Terminal") { model.openInTerminal(update) }
                } else {
                    Button("Retry") { model.install([update]) }
                }
            }
        case nil:
            if update.source == .macOS {
                Button("Open Software Update") { model.update(update) }
            } else if update.source != .summon {
                Button("Update") { model.update(update) }
            }
        }
    }
}

#Preview("Updates") {
    UpdatesView(model: .previewUpdates())
}

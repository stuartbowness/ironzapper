import SwiftUI
import AppKit
import ServiceManagement

struct ContentView: View {
    @Bindable var model: AppModel
    @State private var targeted = false
    @State private var showDetails = Set<String>()
    @State private var showScanNotes = false
    private let accent = Color.primary
    var body: some View {
        VStack(spacing: 0) {
            switch model.phase {
            case .idle: idle
            case .scanning: scanning
            case .review: review
            case .removing: removing
            case .result: result
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .dropDestination(for: URL.self) { urls, _ in
            guard urls.count == 1, !model.busy, let url = urls.first else { return false }
            model.scan(url); return true
        } isTargeted: { targeted = $0 }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in model.refreshHelper() }
        .alert("Iron Zapper", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK", role: .cancel) { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
        .alert("Quit \(model.report?.app.name ?? "the app") first?", isPresented: $model.showQuitConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Quit and Move to Trash", role: .destructive) { model.quitAndRemove() }
        } message: { Text("Save your work before continuing. Iron Zapper will ask the app to quit normally.") }
    }
    private var idle: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 20)
            Image(nsImage: NSImage(named: "IconArtwork") ?? NSImage(named: NSImage.applicationIconName)!)
                .resizable().scaledToFit().frame(width: 132, height: 132)
                .accessibilityHidden(true)
                .padding(.bottom, 20)
            Text("Ready to zap.").font(.system(size: 30, weight: .semibold, design: .rounded))
            Text("Remove an app. Find what it leaves behind.")
                .font(.system(size: 14)).foregroundStyle(.secondary).padding(.top, 8)
            VStack(spacing: 13) {
                Image(systemName: "square.and.arrow.down").font(.system(size: 28, weight: .light)).foregroundStyle(accent)
                Text(targeted ? "Drop to see what it leaves behind" : "Drop an application here").font(.system(size: 16, weight: .medium))
                Button("Choose Application…") { model.choose() }
                    .buttonStyle(.glass).controlSize(.large)
                    .keyboardShortcut("o", modifiers: .command)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 28)
            // A translucent well lets the window's glass show through without a second glass rim.
            .background {
                RoundedRectangle(cornerRadius: 22)
                    .fill(.black.opacity(targeted ? 0.16 : 0.24)
                        .shadow(.inner(color: .black.opacity(0.28), radius: 5, x: 0, y: 3)))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 22)
                    .strokeBorder(Color.primary.opacity(targeted ? 0.45 : 0.10), lineWidth: 1)
                    .allowsHitTesting(false)
            }
            .animation(.easeInOut(duration: 0.18), value: targeted)
            .padding(.top, 30)
            Spacer(minLength: 26)
            Label("Review first. Everything goes to Trash.", systemImage: "checkmark.shield")
                .font(.system(size: 12)).foregroundStyle(.secondary).padding(.bottom, 24)
        }.padding(.horizontal, 46)
    }
    private var scanning: some View {
        VStack(spacing: 18) {
            ProgressView().controlSize(.large)
            Text("Finding every trace…").font(.title2.weight(.semibold))
            Text(model.currentOperation).foregroundStyle(.secondary)
            Text("Checking preferences, support files and background services.")
                .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button("Cancel") { model.reset() }.buttonStyle(.glass).padding(.top, 8)
        }.padding(40)
    }
    private var review: some View {
        VStack(spacing: 0) {
            appHeader
            Divider().padding(.horizontal, 24)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(Category.allCases, id: \.self) { category in
                        let items = model.report?.candidates.filter { $0.category == category } ?? []
                        if !items.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(category.rawValue.uppercased()).font(.system(size: 10, weight: .semibold)).tracking(1.3).foregroundStyle(.secondary)
                                VStack(spacing: 0) {
                                    ForEach(items) { item in
                                        candidateRow(item)
                                        if item.id != items.last?.id { Divider().padding(.leading, 42) }
                                    }
                                }.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 12))
                            }
                        }
                    }
                    scanNotes
                }.padding(24)
            }
            footer
        }
    }
    private var appHeader: some View {
        HStack(spacing: 14) {
            Image(nsImage: model.appIcon).resizable().frame(width: 56, height: 56).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text("Review “\(model.report?.app.name ?? "Application")”").font(.system(size: 20, weight: .semibold))
                Text("Selected items will be moved to Trash.").font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(size(model.selectedBytes)).font(.system(size: 22, weight: .medium, design: .rounded)).monospacedDigit()
                Text("selected").font(.caption).foregroundStyle(.secondary)
            }
        }.padding(24)
    }
    private func candidateRow(_ item: Candidate) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Toggle(isOn: Binding(get: { model.selected.contains(item.id) }, set: { on in if on { model.selected.insert(item.id) } else { model.selected.remove(item.id) } })) {
                    Text(item.url.lastPathComponent).lineLimit(1).truncationMode(.middle)
                }
                .toggleStyle(.checkbox).disabled(!item.selectable)
                .accessibilityHint(item.reason)
                if !item.selectable { Image(systemName: "lock.fill").font(.caption).foregroundStyle(.secondary).help(item.reason) }
                else if item.ownership == .uncertain { Image(systemName: "questionmark.circle").foregroundStyle(.orange).help(item.reason) }
                if item.privileged { Image(systemName: "person.badge.key.fill").font(.caption).foregroundStyle(.secondary).help("System-wide item") }
                Spacer(minLength: 4)
                Text((item.sizeComplete ? "" : "≥ ") + size(item.bytes)).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                Button { if showDetails.contains(item.id) { showDetails.remove(item.id) } else { showDetails.insert(item.id) } } label: {
                    Image(systemName: showDetails.contains(item.id) ? "chevron.up" : "chevron.down").font(.system(size: 10, weight: .semibold)).frame(width: 16, height: 20)
                }.buttonStyle(.plain).accessibilityLabel("Details for \(item.url.lastPathComponent)")
            }
            if showDetails.contains(item.id) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(item.reason).font(.caption).foregroundStyle(.secondary)
                    Text(item.url.path).font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([item.url]) }.font(.caption).buttonStyle(.link)
                }.padding(.leading, 24)
            }
        }.padding(12)
    }
    private var scanNotes: some View {
        DisclosureGroup(isExpanded: $showScanNotes) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Application data may include profiles, databases and other saved work. Shared and unverified system files stay in place.")
                ForEach(model.report?.warnings ?? [], id: \.self) { Text($0) }
                Button("Open Full Disk Access Settings") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!)
                }.buttonStyle(.link)
            }.font(.caption).foregroundStyle(.secondary).padding(.top, 8)
        } label: {
            Label("Scan coverage & preserved files", systemImage: "info.circle").font(.caption).foregroundStyle(.secondary)
        }
    }
    private var footer: some View {
        VStack(spacing: 12) {
            if model.systemSelection && model.helperStatus != .enabled {
                HStack {
                    Label("System cleanup needs approval", systemImage: "lock.shield").font(.caption)
                    Spacer()
                    Button(model.helperStatus == .requiresApproval ? "Open Settings…" : "Enable…") { model.enableHelper() }.buttonStyle(.glass)
                }
            }
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(model.selected.count) items selected").font(.callout.weight(.medium))
                    Text("You can recover files from Trash.").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button { model.beginRemoval() } label: { Label("Zap!", systemImage: "bolt.fill") }
                    .buttonStyle(.glass).controlSize(.large)
                    .disabled(model.selectedCandidates.isEmpty)
            }
        }.padding(20).glassEffect(.regular, in: RoundedRectangle(cornerRadius: 20)).padding([.horizontal, .bottom], 12)
    }
    private var removing: some View {
        VStack(spacing: 20) {
            Image(systemName: "trash").font(.system(size: 42, weight: .light)).foregroundStyle(accent)
            Text("Zapping…").font(.title2.weight(.semibold))
            ProgressView(value: model.progress).frame(width: 240)
            Text(model.currentOperation).font(.callout).foregroundStyle(.secondary).lineLimit(2)
            Text("Keep Iron Zapper open until cleanup finishes.").font(.caption).foregroundStyle(.secondary)
        }.padding(40)
    }
    private var result: some View {
        let succeeded = model.outcomes.filter(\.succeeded)
        let failed = model.outcomes.filter { !$0.succeeded }
        let preserved = model.report?.candidates.filter { item in !model.outcomes.contains { $0.originalPath == item.id } } ?? []
        return VStack(spacing: 0) {
            VStack(spacing: 12) {
                Image(systemName: failed.isEmpty ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .font(.system(size: 46)).foregroundStyle(failed.isEmpty ? accent : .orange)
                Text(failed.isEmpty ? "Zap complete." : "Some items stayed behind.").font(.system(size: 23, weight: .semibold, design: .rounded))
                Text("\(succeeded.count) items moved to Trash" + (failed.isEmpty ? "" : " · \(failed.count) not removed"))
                    .foregroundStyle(.secondary).font(.callout)
            }.padding(28)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(model.outcomes) { outcome in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: outcome.succeeded ? "checkmark" : "exclamationmark.triangle").foregroundStyle(outcome.succeeded ? accent : .orange)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(URL(fileURLWithPath: outcome.originalPath).lastPathComponent).font(.callout.weight(.medium))
                                Text(outcome.message).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    if !preserved.isEmpty {
                        DisclosureGroup("\(preserved.count) unselected or protected items preserved") {
                            ForEach(preserved) { item in Text(item.url.path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
                        }.font(.caption)
                    }
                    scanNotes
                }
                .frame(maxWidth: 420, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, 28)
                .padding(.bottom, 20)
            }
            HStack(spacing: 12) {
                Button("Open Trash") { NSWorkspace.shared.open(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash")) }.buttonStyle(.glass)
                Button("Remove Another App") { model.reset() }.buttonStyle(.glass)
            }.controlSize(.large).padding(24)
        }
    }
    private func size(_ bytes: Int64) -> String { ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) }
}

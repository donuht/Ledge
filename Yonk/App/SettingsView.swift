import AppKit
import KeyboardShortcuts
import SwiftUI

/// 설정 창 내용.
struct SettingsView: View {
    @Bindable var settings: AppSettings
    @State private var runningApps: [NSRunningApplication] = []
    @State private var selectedAppToAdd: String = ""

    var body: some View {
        Form {
            Section("선반") {
                Picker("위치", selection: $settings.edge) {
                    ForEach(ShelfEdge.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                Picker("나타나는 조건", selection: $settings.showTrigger) {
                    ForEach(ShowTrigger.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Text(triggerHelp)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("단축키") {
                KeyboardShortcuts.Recorder("선반 보기/숨기기", name: .toggleShelf)
                KeyboardShortcuts.Recorder("Finder 선택 파일 추가", name: .addFinderSelection)
            }

            Section("일반") {
                Toggle("로그인 시 실행", isOn: Binding(
                    get: { _ = settings.launchAtLoginVersion; return settings.launchAtLogin },
                    set: { settings.launchAtLogin = $0 }
                ))
            }

            Section {
                ignoredList
                HStack {
                    Picker("앱 추가", selection: $selectedAppToAdd) {
                        Text("실행 중인 앱 선택…").tag("")
                        ForEach(runningApps, id: \.bundleIdentifier) { app in
                            Text(app.localizedName ?? app.bundleIdentifier ?? "?").tag(app.bundleIdentifier ?? "")
                        }
                    }
                    Button("추가") {
                        guard !selectedAppToAdd.isEmpty else { return }
                        settings.addIgnored(bundleID: selectedAppToAdd)
                        selectedAppToAdd = ""
                    }
                    .disabled(selectedAppToAdd.isEmpty)
                }
            } header: {
                Text("이 앱에서는 나타나지 않기")
            } footer: {
                Text("드래그를 시작한 순간 맨 앞에 있는 앱 기준입니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 440, height: 520)
        .onAppear(perform: refreshRunningApps)
    }

    private var triggerHelp: String {
        switch settings.showTrigger {
        case .dragStart: "드래그를 시작하면 바로 나타나고, 비어 있으면 사라집니다."
        case .edge: "파일을 끌고 화면의 \(settings.edge.title) 가장자리에 닿으면 나타나고, 비어 있으면 사라집니다."
        }
    }

    @ViewBuilder
    private var ignoredList: some View {
        if settings.ignoredBundleIDs.isEmpty {
            Text("없음").foregroundStyle(.secondary)
        } else {
            ForEach(settings.ignoredBundleIDs, id: \.self) { id in
                HStack {
                    Text(displayName(for: id))
                    Spacer()
                    Button {
                        settings.removeIgnored(bundleID: id)
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
    }

    private func displayName(for bundleID: String) -> String {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return FileManager.default.displayName(atPath: url.path)
        }
        return bundleID
    }

    private func refreshRunningApps() {
        let me = Bundle.main.bundleIdentifier
        runningApps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != nil && $0.bundleIdentifier != me }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
    }
}

/// 설정 창. 메뉴바 앱이라 열 때 앱을 활성화한다.
@MainActor
final class SettingsWindowController {
    private var window: NSWindow?

    func show() {
        if window == nil {
            let hosting = NSHostingController(rootView: SettingsView(settings: .shared))
            let window = NSWindow(contentViewController: hosting)
            window.title = "Yonk 설정"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            // 그룹 Form은 고유 높이가 없어 창이 제목줄만 남도록 줄어든다. 크기를 명시한다.
            window.setContentSize(NSSize(width: 440, height: 520))
            window.center()
            self.window = window
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}

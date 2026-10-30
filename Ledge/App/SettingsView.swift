import AppKit
import KeyboardShortcuts
import SwiftUI

/// 설정 창 내용.
struct SettingsView: View {
    @Bindable var settings: AppSettings
    @State private var runningApps: [NSRunningApplication] = []
    @State private var selectedAppToAdd: String = ""
    @State private var selectedClipboardAppToAdd: String = ""

    var body: some View {
        Form {
            Section("선반") {
                Picker("위치", selection: $settings.edge) {
                    ForEach(ShelfEdge.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                Picker("크기", selection: $settings.size) {
                    ForEach(ShelfSize.allCases, id: \.self) { size in
                        if size != .custom || settings.size == .custom { Text(size.title).tag(size) }
                    }
                }
                .pickerStyle(.segmented)
                Text("선반 안쪽 모서리를 끌어 직접 늘일 수도 있습니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker("나타나는 조건", selection: $settings.showTrigger) {
                    ForEach(ShowTrigger.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Text(verbatim: triggerHelp)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if settings.showTrigger == .cursor {
                    HStack {
                        Slider(value: $settings.cursorPauseDelay, in: 0...2, step: 0.1) {
                            Text("멈춘 뒤 나타나기까지")
                        }
                        Text(settings.cursorPauseDelay <= 0 ? String(localized: "바로") : String(format: String(localized: "%.1f초"), settings.cursorPauseDelay))
                            .monospacedDigit()
                            .frame(width: 44, alignment: .trailing)
                    }
                }
                HStack {
                    Slider(value: $settings.autoHideDelay, in: 0.2...3, step: 0.1) {
                        Text("비면 사라지기까지")
                    }
                    Text(String(format: String(localized: "%.1f초"), settings.autoHideDelay))
                        .monospacedDigit()
                        .frame(width: 44, alignment: .trailing)
                }
            }

            Section("단축키") {
                KeyboardShortcuts.Recorder(String(localized: "선반 보기/숨기기"), name: .toggleShelf)
                KeyboardShortcuts.Recorder(String(localized: "Finder 선택 파일 추가"), name: .addFinderSelection)
                KeyboardShortcuts.Recorder(String(localized: "클립보드 내용 추가"), name: .addClipboard)
            }

            Section("일반") {
                Toggle("맥을 켜면 자동으로 실행", isOn: Binding(
                    get: { _ = settings.launchAtLoginVersion; return settings.launchAtLogin },
                    set: { settings.launchAtLogin = $0 }
                ))
                HStack {
                    Picker("언어", selection: $settings.appLanguage) {
                        Text("시스템 설정 따름").tag("")
                        Text("한국어").tag("ko")
                        Text("English").tag("en")
                    }
                    Button("다시 실행") { relaunch() }
                }
                Text("언어는 다시 실행하면 적용됩니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("클립보드 기록 켜기", isOn: $settings.clipboardHistoryEnabled)
                if settings.clipboardHistoryEnabled {
                    KeyboardShortcuts.Recorder(String(localized: "기록 창 열기"), name: .showClipboardHistory)
                    Picker("보관 개수", selection: $settings.clipboardMaxItems) {
                        Text("100개").tag(100)
                        Text("500개").tag(500)
                        Text("1,000개").tag(1000)
                        Text("무제한").tag(0)
                    }
                    Picker("보관 기간", selection: $settings.clipboardMaxAgeDays) {
                        Text("하루").tag(1)
                        Text("일주일").tag(7)
                        Text("한 달").tag(30)
                        Text("무제한").tag(0)
                    }
                    clipboardIgnoredList
                    HStack {
                        Picker("제외 앱 추가", selection: $selectedClipboardAppToAdd) {
                            Text("실행 중인 앱 선택…").tag("")
                            ForEach(runningApps, id: \.bundleIdentifier) { app in
                                Text(app.localizedName ?? app.bundleIdentifier ?? "?").tag(app.bundleIdentifier ?? "")
                            }
                        }
                        Button("추가") {
                            guard !selectedClipboardAppToAdd.isEmpty else { return }
                            settings.addClipboardIgnored(bundleID: selectedClipboardAppToAdd)
                            selectedClipboardAppToAdd = ""
                        }
                        .disabled(selectedClipboardAppToAdd.isEmpty)
                    }
                }
            } header: {
                Text("클립보드 기록")
            } footer: {
                Text("복사(⌘C)한 글·이미지·파일을 기억해 두었다가 다시 꺼냅니다. 다른 클립보드 앱을 쓰고 있으면 꺼 두세요. 비밀번호 관리자가 숨김 표시한 복사는 기록하지 않습니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
        .frame(width: 460, height: 760)
        .onAppear(perform: refreshRunningApps)
    }

    private func relaunch() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, _ in
            Task { @MainActor in NSApp.terminate(nil) }
        }
    }

    private var triggerHelp: String {
        switch settings.showTrigger {
        case .dragStart: String(localized: "드래그를 시작하면 바로 나타나고, 비어 있으면 사라집니다.")
        case .edge: String(localized: "파일을 끌고 화면의 \(settings.edge.title) 가장자리에 닿으면 나타나고, 비어 있으면 사라집니다.")
        case .cursor: String(localized: "끌다가 잠시 멈추면 커서 옆에 나타나고, 비어 있으면 사라집니다. 창 사이로 휙 옮기는 짧은 드래그에는 뜨지 않습니다.")
        }
    }

    @ViewBuilder
    private var clipboardIgnoredList: some View {
        if settings.clipboardIgnoredBundleIDs.isEmpty {
            Text("제외 앱 없음").foregroundStyle(.secondary)
        } else {
            ForEach(settings.clipboardIgnoredBundleIDs, id: \.self) { id in
                HStack {
                    Text(displayName(for: id))
                    Spacer()
                    Button {
                        settings.removeClipboardIgnored(bundleID: id)
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                }
            }
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
            window.title = String(localized: "Ledge 설정")
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            // 그룹 Form은 고유 높이가 없어 창이 제목줄만 남도록 줄어든다. 크기를 명시한다.
            window.setContentSize(NSSize(width: 460, height: 760))
            window.center()
            self.window = window
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}

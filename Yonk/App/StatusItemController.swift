import AppKit

/// 메뉴바 아이콘. 왼쪽 클릭 = 선반 표시/숨김, 오른쪽 클릭 = 메뉴.
@MainActor
final class StatusItemController: NSObject {
    private let statusItem: NSStatusItem
    private let shelf: ShelfPanelController
    private let menu = NSMenu()
    private let toggleItem: NSMenuItem
    private var settingsWindow: NSWindow?

    init(shelf: ShelfPanelController) {
        self.shelf = shelf
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        toggleItem = NSMenuItem(title: "선반 숨기기", action: #selector(toggleShelf), keyEquivalent: "")
        super.init()

        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: "tray.and.arrow.down.fill", accessibilityDescription: "Yonk")
            image?.isTemplate = true
            button.image = image
            button.toolTip = "Yonk — 클릭: 선반 표시/숨김, 오른쪽 클릭: 메뉴"
            button.target = self
            button.action = #selector(statusButtonClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        toggleItem.target = self
        menu.addItem(toggleItem)
        menu.addItem(.separator())
        let settings = NSMenuItem(title: "설정…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Yonk 종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        menu.addItem(quit)
        menu.delegate = self
    }

    @objc private func statusButtonClicked() {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp || event.modifierFlags.contains(.control) {
            // 메뉴를 잠깐 붙여서 띄우고, 닫히면 떼어낸다(왼쪽 클릭은 메뉴 없이 토글).
            statusItem.menu = menu
            statusItem.button?.performClick(nil)
        } else {
            toggleShelf()
        }
    }

    @objc private func toggleShelf() {
        shelf.toggle()
    }

    @objc private func openSettings() {
        if settingsWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 360, height: 180),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = "Yonk 설정"
            window.isReleasedWhenClosed = false
            window.center()
            let label = NSTextField(wrappingLabelWithString: "설정 항목은 다음 단계(P2 자동 등장, P5 다듬기)에서 추가됩니다.")
            label.frame = NSRect(x: 20, y: 70, width: 320, height: 60)
            label.alignment = .center
            window.contentView?.addSubview(label)
            settingsWindow = window
        }
        NSApp.activate()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}

extension StatusItemController: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        toggleItem.title = shelf.isVisible ? "선반 숨기기" : "선반 보기"
    }

    func menuDidClose(_ menu: NSMenu) {
        statusItem.menu = nil
    }
}

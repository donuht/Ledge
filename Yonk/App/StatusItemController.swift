import AppKit

/// 메뉴바 아이콘. 왼쪽 클릭 = 선반 표시/숨김, 오른쪽 클릭 = 메뉴.
@MainActor
final class StatusItemController: NSObject {
    private let statusItem: NSStatusItem
    private let shelf: ShelfPanelController
    private let menu = NSMenu()
    private let toggleItem: NSMenuItem
    private var settingsWindow: NSWindow?
    private var edgeMenu: NSMenu?

    init(shelf: ShelfPanelController) {
        self.shelf = shelf
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        toggleItem = NSMenuItem(title: "선반 숨기기", action: #selector(toggleShelf), keyEquivalent: "")
        super.init()

        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: "tray.and.arrow.down.fill", accessibilityDescription: "Yonk")
            image?.isTemplate = true
            button.image = image
            button.toolTip = "Yonk — 드래그하면 선반이 나타납니다. 클릭: 선반 고정/숨김, 오른쪽 클릭: 메뉴"
            button.target = self
            button.action = #selector(statusButtonClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        toggleItem.target = self
        menu.addItem(toggleItem)
        menu.addItem(.separator())

        let edgeItem = NSMenuItem(title: "선반 위치", action: nil, keyEquivalent: "")
        let edgeMenu = NSMenu(title: "선반 위치")
        for edge in ShelfEdge.allCases {
            let item = NSMenuItem(title: edge.title, action: #selector(selectEdge(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = edge.rawValue
            edgeMenu.addItem(item)
        }
        edgeItem.submenu = edgeMenu
        menu.addItem(edgeItem)
        self.edgeMenu = edgeMenu
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
        shelf.toggleByUser()
    }

    @objc private func selectEdge(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let edge = ShelfEdge(rawValue: raw) else { return }
        shelf.edge = edge
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
            let label = NSTextField(wrappingLabelWithString: "선반 위치는 메뉴바 아이콘 오른쪽 클릭 → 선반 위치에서 바꿉니다.\n나머지 설정은 다음 단계에서 추가됩니다.")
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
        for item in edgeMenu?.items ?? [] {
            item.state = (item.representedObject as? String) == shelf.edge.rawValue ? .on : .off
        }
    }

    func menuDidClose(_ menu: NSMenu) {
        statusItem.menu = nil
    }
}

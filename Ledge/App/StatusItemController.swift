import AppKit

/// 메뉴바 아이콘. 클릭하면 메뉴(선반 보기/숨기기·위치·나타나는 조건·설정·종료).
@MainActor
final class StatusItemController: NSObject {
    private let statusItem: NSStatusItem
    private let shelf: ShelfPanelController
    private let menu = NSMenu()
    private let toggleItem: NSMenuItem
    private let settingsWindow = SettingsWindowController()
    private var edgeMenu: NSMenu?
    private var triggerMenu: NSMenu?
    private var sizeMenu: NSMenu?
    private let clipboardItem: NSMenuItem
    weak var clipboard: ClipboardController?

    init(shelf: ShelfPanelController) {
        self.shelf = shelf
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        toggleItem = NSMenuItem(title: "선반 숨기기", action: #selector(toggleShelf), keyEquivalent: "")
        clipboardItem = NSMenuItem(title: "클립보드 기록…", action: #selector(showClipboard), keyEquivalent: "")
        super.init()

        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: "tray.and.arrow.down.fill", accessibilityDescription: "Ledge")
            image?.isTemplate = true
            button.image = image
            button.toolTip = "Ledge — 파일을 끌고 화면 가장자리에 닿으면 선반이 나타납니다"
        }
        statusItem.menu = menu

        toggleItem.target = self
        menu.addItem(toggleItem)
        let paste = NSMenuItem(title: "클립보드 내용 추가", action: #selector(addFromClipboard), keyEquivalent: "")
        paste.target = self
        menu.addItem(paste)
        clipboardItem.target = self
        menu.addItem(clipboardItem)
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

        let sizeItem = NSMenuItem(title: "선반 크기", action: nil, keyEquivalent: "")
        let sizeMenu = NSMenu(title: "선반 크기")
        for size in ShelfSize.allCases where size != .custom {
            let item = NSMenuItem(title: size.title, action: #selector(selectSize(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = size.rawValue
            sizeMenu.addItem(item)
        }
        sizeItem.submenu = sizeMenu
        menu.addItem(sizeItem)
        self.sizeMenu = sizeMenu

        let triggerItem = NSMenuItem(title: "나타나는 조건", action: nil, keyEquivalent: "")
        let triggerMenu = NSMenu(title: "나타나는 조건")
        for trigger in ShowTrigger.allCases {
            let item = NSMenuItem(title: trigger.title, action: #selector(selectTrigger(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = trigger.rawValue
            triggerMenu.addItem(item)
        }
        triggerItem.submenu = triggerMenu
        menu.addItem(triggerItem)
        self.triggerMenu = triggerMenu
        menu.addItem(.separator())
        let settings = NSMenuItem(title: "설정…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Ledge 종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        menu.addItem(quit)
        menu.delegate = self
    }

    @objc private func showClipboard() {
        clipboard?.showWindow()
    }

    @objc private func addFromClipboard() {
        shelf.addFromClipboard()
    }

    @objc private func toggleShelf() {
        shelf.toggleByUser()
    }

    @objc private func selectEdge(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let edge = ShelfEdge(rawValue: raw) else { return }
        AppSettings.shared.edge = edge
    }

    @objc private func selectSize(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let size = ShelfSize(rawValue: raw) else { return }
        AppSettings.shared.size = size
    }

    @objc private func selectTrigger(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let trigger = ShowTrigger(rawValue: raw) else { return }
        AppSettings.shared.showTrigger = trigger
    }

    @objc private func openSettings() {
        settingsWindow.show()
    }
}

extension StatusItemController: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        toggleItem.title = shelf.isVisible ? "선반 숨기기" : "선반 보기"
        clipboardItem.isHidden = !AppSettings.shared.clipboardHistoryEnabled
        for item in edgeMenu?.items ?? [] {
            item.state = (item.representedObject as? String) == AppSettings.shared.edge.rawValue ? .on : .off
        }
        for item in sizeMenu?.items ?? [] {
            item.state = (item.representedObject as? String) == AppSettings.shared.size.rawValue ? .on : .off
        }
        for item in triggerMenu?.items ?? [] {
            item.state = (item.representedObject as? String) == AppSettings.shared.showTrigger.rawValue ? .on : .off
        }
    }
}

import AppKit
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    /// 선반 표시/숨김. 기본 ⌃⌥Y.
    static let toggleShelf = Self("toggleShelf", default: .init(.y, modifiers: [.control, .option]))
    /// Finder에서 선택한 파일을 선반에 추가. 기본 ⌃⌥⇧Y.
    static let addFinderSelection = Self("addFinderSelection", default: .init(.y, modifiers: [.control, .option, .shift]))
    /// 클립보드 내용을 선반에 추가. 기본 ⌃⌥V.
    static let addClipboard = Self("addClipboard", default: .init(.v, modifiers: [.control, .option]))
}

/// 전역 단축키(Carbon 핫키 기반, 접근성 권한 불필요).
@MainActor
final class HotkeyController {
    private let shelf: ShelfPanelController

    init(shelf: ShelfPanelController) {
        self.shelf = shelf
        KeyboardShortcuts.onKeyUp(for: .toggleShelf) { [weak self] in
            self?.shelf.toggleByUser()
        }
        KeyboardShortcuts.onKeyUp(for: .addFinderSelection) { [weak self] in
            self?.addFinderSelection()
        }
        KeyboardShortcuts.onKeyUp(for: .addClipboard) { [weak self] in
            self?.shelf.addFromClipboard()
        }
    }

    /// Finder의 현재 선택을 AppleScript로 받아 선반에 올린다. 처음 한 번 자동화 권한 창이 뜬다.
    private func addFinderSelection() {
        let urls = FinderSelection.currentURLs()
        guard !urls.isEmpty else {
            NSSound.beep()
            return
        }
        shelf.store.add(urls: urls)
        if !shelf.isVisible { shelf.toggleByUser() }
    }
}

enum FinderSelection {
    private static let script = """
    tell application "Finder"
        set out to {}
        repeat with f in (get selection)
            set end of out to POSIX path of (f as alias)
        end repeat
        return out
    end tell
    """

    static func currentURLs() -> [URL] {
        var error: NSDictionary?
        guard let result = NSAppleScript(source: script)?.executeAndReturnError(&error) else {
            NSLog("Yonk: Finder 선택 읽기 실패: \(error ?? [:])")
            return []
        }
        var urls: [URL] = []
        if result.numberOfItems > 0 {
            for i in 1...result.numberOfItems {
                if let path = result.atIndex(i)?.stringValue { urls.append(URL(fileURLWithPath: path)) }
            }
        } else if let path = result.stringValue, !path.isEmpty {
            urls.append(URL(fileURLWithPath: path))
        }
        return urls
    }
}

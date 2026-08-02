import Cocoa

/// Terminals need different treatment when replacing text.
///
/// Everywhere else, pasting over a selection replaces it. In a terminal the
/// shell owns the cursor and the on-screen selection is just highlighting, so a
/// paste always *inserts* — typing "hello" and converting it would leave
/// "helloруддщ". Those apps have to have the characters deleted first.
enum TerminalApps {

    private static let bundleIDs: Set<String> = [
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "dev.warp.Warp-Stable",
        "net.kovidgoyal.kitty",
        "io.alacritty",
        "com.mitchellh.ghostty",
        "co.zeit.hyper",
        "org.tabby",
    ]

    static var isFrontmost: Bool {
        guard let id = NSWorkspace.shared.frontmostApplication?.bundleIdentifier else {
            return false
        }
        return bundleIDs.contains(id)
    }
}

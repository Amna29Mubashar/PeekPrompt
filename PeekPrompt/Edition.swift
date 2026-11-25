import SwiftUI

// PeekPrompt comes in two editions built from this same code:
//
//  • Free (this open-source repo): everything here works on its own.
//  • Pro (the App Store edition): adds features such as Word Tracking, Magic Polish,
//    Presentation and Memorize modes, folders and the phone remote. Those live in a
//    separate project that plugs in through `ProFeatures` below.
//
// In the free edition `Edition.pro` is nil, so every Pro hook simply does nothing.

/// What the Pro edition provides. The free edition never implements this.
protocol ProFeatures: AnyObject {
    /// True while the user has an active Pro subscription.
    var isUnlocked: Bool { get }
    /// Shows the upgrade screen.
    func showUpgrade()

    // Presentation & Memorize modes
    func segments(for script: String, presentation: Bool, memorize: Bool) -> [String]
    func memorize(_ text: String, level: Int, revealUpTo: Int) -> String

    // Word Tracking & Auto speed
    func loadTracking(text: String)
    func startListening(measureOnly: Bool)
    func stopListening()
    func resetTracking()
    /// How far through the text you've read (0...1).
    var trackedFraction: Double { get }
    var trackingFinished: Bool { get }
    var trackedWordCount: Int { get }
    var wordsPerMinute: Double? { get }

    // Import
    var importExtensions: [String] { get }
    /// Returns nil for file types Pro doesn't handle.
    func importText(from url: URL) throws -> String?

    // Extra Settings UI
    func view(for slot: ProSlot) -> AnyView?
}

/// Places in the interface where the Pro edition adds its own controls.
enum ProSlot {
    case scriptLibrary       // library list with folders (replaces the simple list)
    case scriptTitleAccessory // folder menu next to the script's title
    case scriptEditorTools   // Magic Polish button
    case scrollingSection    // Presentation & Memorize settings
    case speedExtras         // Auto speed and pacing timer rows
    case privacySection      // phone remote
    case menuItems           // extra items in the menu bar menu
}

enum Edition {
    /// Set at launch by the Pro edition. Always nil in the free edition.
    static var pro: ProFeatures?

    /// True when this build includes Pro features (the App Store edition).
    static var isProBuild: Bool { pro != nil }
    /// True when Pro features are unlocked.
    static var hasPro: Bool { pro?.isUnlocked ?? false }

    /// Scrolling modes to offer in menus and Settings.
    static var availableModes: [ScrollMode] {
        isProBuild ? ScrollMode.allCases : [.classic, .voiceActivated]
    }

    /// e.g. "Word Tracking · Pro" while Pro is locked.
    static func label(for mode: ScrollMode) -> String {
        mode == .wordTracking && isProBuild && !hasPro ? mode.title + " · Pro" : mode.title
    }

    /// Ends of script to offer: "Play the next script" needs the Pro play queue.
    static var availableEndActions: [EndAction] {
        isProBuild ? EndAction.allCases : [.stop, .loop]
    }
}

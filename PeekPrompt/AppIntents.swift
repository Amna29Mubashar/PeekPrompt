import AppIntents

// Actions for Siri, Spotlight and the Shortcuts app.
// e.g. "Hey Siri, start PeekPrompt" or "Next slide in PeekPrompt".

struct StartPrompterIntent: AppIntent {
    static var title: LocalizedStringResource = "Start Prompter"
    static var description = IntentDescription("Shows the prompter and starts scrolling (or listening, in voice modes).")
    static var openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult {
        PrompterSettings.shared.isPrompterVisible = true
        if !ScrollEngine.shared.isRunning { ScrollEngine.shared.play() }
        return .result()
    }
}

struct PausePrompterIntent: AppIntent {
    static var title: LocalizedStringResource = "Pause Prompter"
    static var description = IntentDescription("Pauses the prompter.")
    static var openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult {
        ScrollEngine.shared.pause()
        return .result()
    }
}

struct RestartPrompterIntent: AppIntent {
    static var title: LocalizedStringResource = "Restart Prompter"
    static var description = IntentDescription("Jumps back to the top of the script.")
    static var openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult {
        ScrollEngine.shared.restart()
        return .result()
    }
}

struct NextSlideIntent: AppIntent {
    static var title: LocalizedStringResource = "Next Slide"
    static var description = IntentDescription("Moves to the next slide or chunk in Presentation or Memorize mode.")
    static var openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult {
        ScrollEngine.shared.nextSegment()
        return .result()
    }
}

struct PreviousSlideIntent: AppIntent {
    static var title: LocalizedStringResource = "Previous Slide"
    static var description = IntentDescription("Goes back one slide or chunk.")
    static var openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult {
        ScrollEngine.shared.previousSegment()
        return .result()
    }
}

/// Phrases Siri understands without any setup. Each must include the app's name.
struct PeekPromptShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartPrompterIntent(),
            phrases: [
                "Start \(.applicationName)",
                "Start my script in \(.applicationName)",
                "Play \(.applicationName)"
            ],
            shortTitle: "Start Prompter",
            systemImageName: "play.fill"
        )
        AppShortcut(
            intent: PausePrompterIntent(),
            phrases: ["Pause \(.applicationName)", "Stop \(.applicationName)"],
            shortTitle: "Pause Prompter",
            systemImageName: "pause.fill"
        )
        AppShortcut(
            intent: RestartPrompterIntent(),
            phrases: ["Restart \(.applicationName)"],
            shortTitle: "Restart Prompter",
            systemImageName: "backward.end.fill"
        )
        AppShortcut(
            intent: NextSlideIntent(),
            phrases: ["Next slide in \(.applicationName)"],
            shortTitle: "Next Slide",
            systemImageName: "chevron.right"
        )
        AppShortcut(
            intent: PreviousSlideIntent(),
            phrases: ["Previous slide in \(.applicationName)"],
            shortTitle: "Previous Slide",
            systemImageName: "chevron.left"
        )
    }
}

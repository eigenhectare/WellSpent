import AppIntents

struct WellSpentWatchShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartWellSpentWatchTimerIntent(),
            phrases: ["Start a timer in \(.applicationName)"],
            shortTitle: "Start Timer", systemImageName: "play.fill")
        AppShortcut(
            intent: PauseWellSpentWatchTimerIntent(),
            phrases: ["Pause my timer in \(.applicationName)"],
            shortTitle: "Pause Timer", systemImageName: "pause.fill")
        AppShortcut(
            intent: ResumeWellSpentWatchTimerIntent(),
            phrases: ["Resume my timer in \(.applicationName)"],
            shortTitle: "Resume Timer", systemImageName: "play.fill")
        AppShortcut(
            intent: SwitchWellSpentWatchProjectIntent(),
            phrases: ["Switch projects in \(.applicationName)"],
            shortTitle: "Switch Project", systemImageName: "arrow.left.arrow.right")
        AppShortcut(
            intent: EndWellSpentWatchTimerIntent(),
            phrases: ["End my timer in \(.applicationName)"],
            shortTitle: "End Timer", systemImageName: "stop.fill")
    }
}

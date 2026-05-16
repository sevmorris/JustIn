import SwiftUI

@main
struct JustInApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var viewModel = AnalyzerViewModel()
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
                .onAppear {
                    appDelegate.onOpenURLs = { viewModel.addFiles($0) }
                    appDelegate.flushPending()

                    let args = CommandLine.arguments.dropFirst()
                        .map { URL(fileURLWithPath: $0) }
                        .filter { FileManager.default.fileExists(atPath: $0.path) }
                    if !args.isEmpty { viewModel.addFiles(args) }
                }
        }
        .commands {
            CommandGroup(replacing: .help) {
                Button("JustIn Help") {
                    openWindow(id: "help")
                }
                .keyboardShortcut("?", modifiers: .command)

                Button("Check for Updates…") {
                    open("https://github.com/sevmorris/JustIn/releases")
                }

                Button("Support JustIn…") {
                    open("https://ko-fi.com/sevmo")
                }

                Divider()

                Button("Send Feedback…") {
                    open("https://github.com/sevmorris/JustIn/issues/new")
                }

                Button("Report an Issue…") {
                    open("https://github.com/sevmorris/JustIn/issues/new")
                }
            }
        }

        Window("JustIn Help", id: "help") {
            HelpView()
        }
        .windowResizability(.contentSize)
    }

    private func open(_ urlString: String) {
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }
}

/// SwiftUI's `.onOpenURL` only delivers a single URL at a time on macOS, so it
/// can't preserve JustIn's "select several files in Finder → Open With JustIn"
/// behavior. A minimal AppKit delegate bridges `application(_:open:)` (and any
/// URLs that arrive before the view model is wired up) into the view model.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var onOpenURLs: (([URL]) -> Void)?
    private var pending: [URL] = []

    func application(_ application: NSApplication, open urls: [URL]) {
        if let onOpenURLs {
            onOpenURLs(urls)
        } else {
            pending.append(contentsOf: urls)
        }
    }

    func flushPending() {
        guard !pending.isEmpty, let onOpenURLs else { return }
        onOpenURLs(pending)
        pending.removeAll()
    }
}

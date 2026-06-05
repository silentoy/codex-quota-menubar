import SwiftUI

@main
struct CodexQuotaMenubarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = QuotaStore()

    var body: some Scene {
        MenuBarExtra {
            ContentView()
                .environmentObject(store)
                .frame(width: 290)
                .onAppear {
                    store.refreshIfStale()
                }
        } label: {
            if store.displayMode == .ring {
                Image(nsImage: MenuBarQuotaIcon.image(
                    snapshot: store.snapshot,
                    lowThreshold: store.lowThreshold,
                    isRefreshing: store.isRefreshing
                ))
                .resizable()
                .frame(width: 22, height: 22)
                .accessibilityLabel(store.accessibilityLabel())
            } else {
                Text(store.menuTitle)
                    .accessibilityLabel(store.accessibilityLabel())
            }
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(store)
                .frame(width: 420)
        }
    }
}

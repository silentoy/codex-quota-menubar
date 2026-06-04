import SwiftUI

@main
struct CodexQuotaMenubarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = QuotaStore()

    var body: some Scene {
        MenuBarExtra {
            ContentView()
                .environmentObject(store)
                .frame(width: 280)
                .onAppear {
                    store.refreshIfStale()
                }
        } label: {
            Text(store.menuTitle)
                .foregroundStyle(store.menuColor)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(store)
                .frame(width: 360)
                .padding()
        }
    }
}

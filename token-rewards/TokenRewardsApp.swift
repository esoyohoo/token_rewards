import SwiftUI
import SwiftData

@main
struct TokenRewardsApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            ProfileEntity.self,
            DayEntry.self
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false, cloudKitDatabase: .automatic)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}

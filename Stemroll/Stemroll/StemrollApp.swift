// 



import SwiftUI

@main
struct StemrollApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(TranscriptionViewModel())
        }
        .defaultSize(width: 900, height: 600)
        .windowResizability(.contentMinSize)
    }
}

// 



import SwiftUI

struct ContentView: View {
    var body: some View {
        HSplitView {
            IOPanelView()
                .frame(minWidth: 340, idealWidth: 380)
            SettingsPanelView()
                .frame(minWidth: 340, idealWidth: 480)
        }
        .frame(minWidth: 680, minHeight: 480)
    }
}

#Preview {
    ContentView()
        .environment(TranscriptionViewModel())
}

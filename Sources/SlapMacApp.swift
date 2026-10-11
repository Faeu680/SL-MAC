import SwiftUI

@main
struct SlapMacApp: App {
    @StateObject private var engine = SlapEngine.shared

    var body: some Scene {
        MenuBarExtra {
            MenuView().environmentObject(engine)
        } label: {
            Image(systemName: engine.justSlapped
                  ? "hand.raised.fingers.spread.fill"
                  : (engine.enabled ? "hand.raised.fill" : "hand.raised.slash"))
        }
        .menuBarExtraStyle(.window)
    }
}

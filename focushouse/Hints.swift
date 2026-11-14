import SwiftUI
import TipKit

/// TipKit popovers for screens outside the Home tour (TipKit popovers don't show
/// on toolbar buttons, so Home uses HomeTour instead). Reset by Settings → Show intro.
struct Hint: Tip {
    let id: String
    let title: Text
    let message: Text?
    let image: Image?

    init(_ id: String, _ title: String, _ message: String, _ symbol: String) {
        self.id = id
        self.title = Text(title)
        self.message = Text(message)
        self.image = Image(systemName: symbol)
    }

    /// Set once the intro pages are closed, so labels never pop up behind them.
    @Parameter static var introDone: Bool = false
    var rules: [Rule] { [#Rule(Self.$introDone) { $0 }] }

    static let calendar = Hint("calendar", "Your month", "Tap a day to see its events and tasks.", "calendar")

    /// Reads the "Show intro" request from last session; call before `Tips.configure`.
    static func setUp() {
        let d = UserDefaults.standard
        if d.bool(forKey: "resetHints") {
            try? Tips.resetDatastore()
            d.removeObject(forKey: "resetHints")
        }
        try? Tips.configure()
        introDone = d.bool(forKey: "seenOnboarding")
    }
}

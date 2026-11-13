import SwiftUI

struct CalendarTipView: View {
    var body: some View {
        List {
            Section {
                Label("Use your Google Calendar", systemImage: "calendar.badge.plus")
                    .font(.headline)
                Text("brickbybrick reads your iPhone Calendar, so adding your Google account to iPhone once and your Google events show up here too.")
            }
            Section("Steps") {
                Text("1. Open the Settings app on your iPhone.")
                Text("2. Go to Apps → Calendar → Calendar Accounts.")
                Text("3. Tap Add Account → Google and sign in.")
                Text("4. Make sure Calendars is switched on.")
            }
            Section {
            } footer: {
                Text("Plans you add to Calendar from brickbybrick will also show up in Google Calendar.")
            }
        }
        .pixelTitle("Google Calendar")
    }
}

#Preview { NavigationStack { CalendarTipView() } }

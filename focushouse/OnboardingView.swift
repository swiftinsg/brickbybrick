import SwiftUI

/// First-launch intro: why focushouse exists and what each part does.
/// Shown once; replay from Settings → "Show intro".
struct OnboardingView: View {
    @AppStorage("seenOnboarding") private var seen = false
    @Environment(\.dismiss) private var dismiss
    @State private var page = 0

    private struct Page {
        let art: String          // asset name
        let title: String
        let text: String
    }

    private var pages: [Page] {
        let ai = Planner.isAvailable
        return [
            Page(art: "house.calm", title: "Welcome to focushouse",
                 text: "Most planners squeeze more work into your day. focushouse looks after you instead: it balances schoolwork with rest, so you don't burn out."),
            Page(art: "house.crumbling", title: "Your house",
                 text: "The house on Home is you: it mirrors your mental health. Several stressful days in a row wear it down, from Calm to Stressed, Overloaded and Crumbling. Put your phone down for 3 hours in a day and it repairs a step."),
            Page(art: "tab.schedule", title: "Schedule",
                 text: ai ? "Type a big goal or a messy to-do list. On-device AI splits it into tasks, guesses how long each takes, and fits them around your routine and Calendar. Edit anything before you accept."
                          : "Add your tasks and how long they take. focushouse fits them around your routine and Calendar. Edit anything before you accept."),
            Page(art: "tab.tasks", title: "Check-ins",
                 text: "You get a reminder when a task starts and a check-in when it ends: Done, or need more time? Your answers teach the app your real pace, so future plans fit you better."),
            Page(art: "icon.brick", title: "Bricks",
                 text: "Finishing tasks earns bricks. Tap the brick counter on Home to spend them on furniture for your house. Bricks decorate, but only rest repairs."),
            Page(art: "tab.calendar", title: "Tasks & Calendar",
                 text: "Tasks holds one-off to-dos with due dates. Calendar shows your iPhone Calendar, including Google Calendar if it's added in iPhone Settings. Change your routine and work limit in Settings (the gear on Home)."),
        ]
    }

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                ForEach(pages.indices, id: \.self) { i in
                    let p = pages[i]
                    VStack(spacing: 24) {
                        Spacer()
                        Image(p.art).pixelArt()
                            .frame(maxWidth: p.art.hasPrefix("house") ? 220 : 96)
                            .accessibilityHidden(true)
                        Text(p.title).font(.pixel(30, relativeTo: .title).weight(.bold))
                            .multilineTextAlignment(.center)
                        Text(p.text).multilineTextAlignment(.center).foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, 32)
                    .tag(i)
                }
            }
            .tabViewStyle(.page)
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            Button {
                if page < pages.count - 1 { withAnimation { page += 1 } } else { finish() }
            } label: {
                Text(page < pages.count - 1 ? "Next" : "Get started")
                    .font(.pixel(20, relativeTo: .headline).weight(.bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity).padding()
                    .pixelBox(.brick)
            }
            .padding()
        }
        .background(Color.paper)
        .overlay(alignment: .topTrailing) {
            if page < pages.count - 1 {
                Button("Skip", action: finish).padding()
            }
        }
        .tint(.brick)
    }

    private func finish() {
        seen = true
        dismiss()
    }
}

#Preview { OnboardingView() }

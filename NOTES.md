# Focusedhouse — Planning Notes

Living notes from the requirements Q&A. Updated after each answer.

## Idea (as stated)
A SwiftUI app using Apple's on-device Foundation Models to:
- automatically decompose a goal into tasks
- recommend a schedule with suggested timings for each task

## Decided
- Name: Focusedhouse
- Repo: public on GitHub
- Platform: iOS SwiftUI app targeting iOS 27.2 (confirmed)
- Input modes (toggle): **Goal mode** (one big goal → tasks spread over days) and **Today mode** (messy to-do dump → tidied, timed, fitted into today)
- Audience: students and teenagers
- Free-time sources (mixed): iOS Calendar + Google Calendar events to schedule around; optional self-set routine (e.g. school hours, bedtime); Settings option to "ask me each time" instead

## Open questions
- Google Calendar: via iOS Calendar account sync (EventKit) or direct Google sign-in/API?
- (more to come)

## Q&A log

**Q2: What does the user type in, and who is it for?**
A: Both modes with a toggle (one big goal / today's to-do dump). Aimed mostly at students and teenagers.

**Q3: How does the app know when the student is free?**
A: A mix: iOS Calendar, Google Calendar, a self-set routine if needed, and an "ask each time" preference in Settings.

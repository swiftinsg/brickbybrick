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
- Google Calendar: read via iOS Calendar account sync (EventKit) — no Google sign-in/API. Onboarding shows a short "connect Google Calendar" tip
- Output: schedule lives in-app with checkboxes + "Add to Calendar" button (writes events to iOS Calendar → syncs to Google). Settings toggle: auto-add to calendar right after a schedule is suggested
- Notifications: app sends its own task-start reminders, plus end-of-task check-ins ("Done? / Need more time?") that reschedule remaining tasks if behind
- Rescheduling: default is simple push-back (+15/+30/+60 min, shifts later tasks; overflow past bedtime → tomorrow, no AI). Plus a "Re-plan with AI" button that has Foundation Models rebuild the rest of the plan
- Editing before accept: full control: rename/add/delete tasks, change durations (auto-reflow), and drag tasks to new slots on a timeline view. "Try again" regenerates
- No Apple Intelligence (older device / turned off): manual mode: student enters tasks + durations; scheduling, calendar, reminders, check-ins still work. AI features (decomposition, estimates, Re-plan with AI) hidden
- History + adaptive estimates (must be personalised): plans and actual durations (from check-ins) saved on-device; per-category estimate-vs-actual ratios fed into the model prompt so estimates adapt over time. No backend/accounts

## Open questions
- Build order / v1 scope
- (more to come)

## Q&A log

**Q2: What does the user type in, and who is it for?**
A: Both modes with a toggle (one big goal / today's to-do dump). Aimed mostly at students and teenagers.

**Q3: How does the app know when the student is free?**
A: A mix: iOS Calendar, Google Calendar, a self-set routine if needed, and an "ask each time" preference in Settings.

**Q4: How should Google Calendar connect?**
A: Option A, via the iOS Calendar account sync (EventKit). No in-app Google sign-in.

**Q5: Where does the generated schedule go?**
A: Both: in-app with checkboxes, plus an "Add to Calendar" button. A toggle can make it add to the calendar automatically once a schedule is suggested.

**Q6: Should the app send its own notifications?**
A: C: its own reminders plus end-of-task check-ins that reschedule when running behind.

**Q7: How does "Need more time" reschedule?**
A: C: simple push-back by default, plus a "Re-plan with AI" button.

**Q8: How much can the student edit a suggested schedule?**
A: C: full control, including a drag-and-drop timeline.

**Q9: What happens on devices without Apple Intelligence?**
A: B: manual mode with the AI features hidden.

**Q10: Should the app learn from the past?**
A: C: keep a history and use it to correct estimates. It must be personalised and adaptive.

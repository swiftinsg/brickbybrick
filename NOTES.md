# brickbybrick — Planning Notes

Living notes from the requirements Q&A. Updated after each answer.

## Idea (as stated)
A SwiftUI app using Apple's on-device Foundation Models to:
- automatically decompose a goal into tasks
- recommend a schedule with suggested timings for each task

## Decided
- Name: brickbybrick
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
- Build in phases, each testable before the next (see Plan)

## Open questions
- None. Plan agreed, waiting for "go"
- (more to come)

## Plan
1. **Core**: Goal/Today toggle → Foundation Models decomposes into tasks + estimates → scheduled into a self-set routine's free time → editable list (rename/add/delete/durations, auto-reflow) → saved on-device (SwiftData). Manual mode when Apple Intelligence is unavailable.
2. **Calendar**: EventKit reads iOS (+ synced Google) events as busy time; Add to Calendar button; auto-add toggle; "ask each time" setting; Google-sync onboarding tip.
3. **Reminders & check-ins**: local notifications at task start; end-of-task "Done? / Need more time?" → +15/30/60 push-back (overflow → tomorrow); "Re-plan with AI" button.
4. **Timeline**: drag-and-drop tasks between time slots.
5. **Adaptive estimates**: record actual durations; per-category actual/estimate ratio injected into the prompt.

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

**Q11: How should it be built?**
A: B: in phases, in the order listed in the Plan.

## Change log (what was built, and decisions made along the way)

### Phase 1: Core (commit 5d8dea6)
- Goal / Today toggle. On-device Foundation Models splits the input into tasks (10–90 min each) with a category, an estimate, and a day number.
- The scheduler is plain code. It puts tasks back to back inside the routine's free time (wake → bed, skipping school hours Mon–Fri). Overflow moves to the next morning.
- Editable list: rename, add, delete, reorder, change minutes. Times reflow automatically. Plans are saved with SwiftData.
- Manual mode ("Enter tasks myself") when Apple Intelligence isn't available. AI buttons are hidden.
- Changed after testing:
  - The plan title is a big inline text field, so you name the list yourself.
  - "Try again" moved to the top toolbar.

### Phase 2: Calendar, priorities, study material (commit 7fe7fdd)
- Calendar events (including Google, synced through iOS Settings) count as busy time. Each plan's own events are ignored, so they don't block it.
- The "Add to Calendar" / "Update Calendar" button sits under the list. There is an auto-add toggle in Settings.
- "Ask each time" setting: the New Plan screen asks for today's free hours instead of using the routine.
- First-launch tip and Settings page explaining how to sync Google Calendar.
- **Priority**: the AI reads "urgent", "!", due dates and "can wait" into high / normal / low. Higher-priority tasks go first within a day. You can change priority from the flag menu on each row.
- **Study material**: paste notes or a syllabus. The AI follows its sections in order and labels each task with its section (e.g. "Section 1: Arenes"). Labels are dropped when no material is given. Material is cut at 6000 characters (small on-device context).

### Phase 3: Reminders and check-ins (commit bb6e095)
- Local notification at each task's start, plus an end-of-task check-in with Done / +15 / +30 / +60 min.
- Push-back is plain code: the task gets longer and later tasks shift. Anything past bedtime moves to tomorrow.
- "Re-plan the rest with AI" rebuilds only the unfinished tasks from now on. Finished tasks keep their times.
- Limit: iOS keeps at most 64 pending notifications, so very long plans only get reminders for the nearest tasks.

### Phase 4: Timeline (in progress, not committed yet)
- A List / Timeline switch at the top of a plan. The timeline shows one day at a time (day chips), hour lines, grey "Busy" Calendar blocks, a red now line, and task blocks (high priority in red).
- It opens scrolled to the first unfinished task.
- Fixed: a big gap at the top, and the timeline not scrolling to the bottom.
- **Moving vs pinning** (changed after feedback):
  - **Drag** a task (press and hold, then drag; snaps to 5 min) or use **Move to day**: the task moves there, but it isn't locked. If earlier tasks run over, it can still be pushed later.
  - **Pin** only happens when *you* choose "Pin to <time>" from the long-press menu, on the list or on the timeline. A pinned task never moves, and the others flow around it. A 📌 shows on pinned tasks. "Unpin time" undoes it.
  - ~~Exception: a high-priority task you drag is pinned where you drop it.~~ Removed: nothing is pinned automatically. After any drag, the app asks "Pin “Task” to 5:00 PM?" (Pin here / Don't pin), so a long-press by accident never locks a task.
  - Moving a task in the list (Edit → drag) clears its drop time and pin, so the list order decides.
- Planning ahead:
  - The New Plan screen has a Start date and time, and in Goal mode a "Finish by" date.
  - The plan's start time can be edited under its name.
  - The AI is told how much free time each day has (from your routine and Calendar), so it doesn't overload a day.
- **Try a different plan**: the AI gets the old plan and is told to make a genuinely different one (different chunking, study method, order and names), with more random sampling. Retrying won't give the same plan back.
- Tidier task rows:
  - Title with a priority flag on the right.
  - Section label under the title.
  - One grey line with the time ("Thu 12 · 4:00 PM–4:45 PM · 45 min"; the date only shows when the tasks span more than one day) and a small −/+ stepper. The 📌 sits beside the title.
  - "Add to Calendar" is centred.

### Polish (after Phase 4 feedback)
- **Small jobs stay whole**: "pay mum", "tidy room" become one 5–20 min task, never split into steps. Only big work (essays, projects, revision) is split.
- **Nothing gets dropped**: the to-do dump is sent one item per line (the model skipped items in long comma lists). Any item still missing is added back as its own 30 min task (urgent if it had "!" or "urgent").
- Priority defaults to normal unless the student marks it. AI titles have no trailing full stop.
- **Calendar button**: once everything is in Calendar it turns into a grey "✓ In Calendar" label. Changing a task brings back "Update Calendar".
- **Layout overhaul** (Apple design principles: hierarchy, grouping, feedback):
  - Plan screen: title, "2 of 5 done · 1 h 45 min left", a progress bar, then tasks grouped under day headers (Today / Tomorrow / weekday) with each day's total. The cards have rounded corners all round.
  - Rows: big check circle (green, with a haptic when ticked), a red ! for high priority, the time range, and a duration chip on the right that opens a duration menu (replaces the −/+ stepper).
  - Priority, "Need more time?" and Pin are in the long-press menu. Swipe right for +15 min.
  - The Calendar button floats in a glass bar at the bottom.
  - Home list: a progress ring per plan. New Plan: a one-line explanation of each mode and one prominent "Make my plan" button.

### Subtasks (from the Figma wireframe)
- The AI returns **items**, and big work comes with 2–5 **subtasks**. Each subtask is a normal task (own time, checkbox, reminder, Calendar event) and stores its item's name in `parent`.
- Quick jobs (pay mum, tidy room) are plain tasks with no subtasks. Code enforces it: chores and one-step items lose their subtasks.
- Study material: one item per section, with that section's tasks as subtasks (this replaces the old section label).
- Code fixes for the small model: dropped to-do lines come back, and "!", "urgent", "due" → high, "maybe", "can wait" → low.
- The list shows a parent row ("Science project poster · 1 of 3 subtasks · 1 h 35 min", tick to finish all of them) with its subtasks indented underneath.
- Not built yet from the wireframe: the tab bar (Tasks / Calendar / Recommended schedule), the filter button, and a New Task sheet with tag / due date / priority.

### Your own subtasks + deleting
- **Subtask editor** (sheet): tap a parent row, or long-press any task → "Edit subtasks" / "Add subtasks". You can rename the task, rename subtasks, change their durations, add, delete and reorder. Closing the sheet saves (Done or swipe down).
  - Adding subtasks to a plain task turns it into a parent. A single subtask named like its task goes back to a plain task. Blank subtasks are dropped.
- **Adaptive subtasks**: every breakdown you save (2+ subtasks) is remembered on device (last 40). The next plan's prompt includes up to 3 saved breakdowns whose names share words with your input ("history essay" matches your "English essay"), and the AI follows them. Tested on the real model: it reused the student's steps and durations exactly.
- **Delete**: swipe left on a task (or long-press → Delete). On a parent row this deletes it with all its subtasks. Swipe left on a plan on the home screen (or long-press → Delete plan). Calendar events and reminders go with them.
  - Why delete didn't work before: the +15 min swipe on task rows turned off SwiftUI's automatic swipe-to-delete. Delete is now an explicit swipe action.
- opencode (GLM 5.3 Flash) wrote the editor screen from a spec. Claude did the model, prompt and wiring, and fixed its save (clashing order values, swipe-to-close not saving).

### Timeline redesign
- Taller (120 pt per hour, was 72), and **pinch to zoom** between 70 and 320 pt per hour. The zoom is remembered.
- **No more overlapping**: short tasks are drawn tall enough to read, and the next block moves down just enough. Labels still show the real times.
- Calendar-style blocks: a tinted card with a coloured bar on the left (red = high priority, grey = done, with a ✓). Big enough blocks show the parent task's name above the title.
- Day chips show "Today" or the weekday, the date, and the number of tasks. Hour labels are short ("4 PM"), with half-hour lines when zoomed in. The now line has a dot, and Busy blocks are dashed outlines.

### Phase 5: Adaptive estimates
- Every AI task keeps its original estimate. The first time it's ticked done, the app records how long it really took:
  - ticked while it's running → time since it started (at least 5 min);
  - ticked after it ended (or "Done ✓" on the check-in) → its length, including any "Need more time" push-backs or duration changes;
  - ticked before it started → unknown, not recorded (so ticking a whole parent ahead of time doesn't skew it).
- Saved on device per category (homework, writing, revision…): the last 20 "real ÷ estimate" ratios. Deleting a plan doesn't erase them.
- Once a category has 5+ finished tasks (was 3; raised so a few odd tasks don't skew it) and you're 10%+ off, the new-plan prompt says e.g. "writing: takes longer than typical, ×1.5 (a typical 30 min writing task takes them about 45 min)".
- Re-plan with AI doesn't get it: the remaining tasks already have adjusted times, so it would scale twice.
- Settings → **My pace** shows each category's ratio and task count, with "Reset my pace".

### How the work was split
- Claude did the harder parts (scheduler, pinning and moving, timeline, prompts, notifications) and reviewed everything.
- Small, mechanical UI edits went to opencode (GLM 5.3 Flash) from written specs. Claude then reviewed and fixed them (e.g. a duplicate button, a Section syntax error, a simplified time label).

### Renamed to brickbybrick (2026-11-12)
- App, Xcode targets, scheme, folders and bundle id (`com.chuahchengxi.brickbybrick`) renamed from Focusedhouse. It installs as a new app, so old on-device data stays in the old one.
- Repo moved to https://github.com/swiftinsg/brickbybrick.

### Calendar home + Tasks inbox (2026-11-12)
- **Calendar tab** (first tab): a custom month grid. A ring round each date fills as the day gets busier (a dot for 1 thing to do, full circle at 6+), and ‹ › change month. No "Today" button: students tap the date instead; below it, everything on the picked day. That's the scheduled tasks from all plans (tick them there; tap to open the plan) plus inbox to-dos due that day ("not planned yet").
- **Tasks tab = inbox**: "Plan these" opens New Plan with every open to-do, one per line. High → "!", low → "(can wait)", due date → "(by Fri 14 Nov)" (not "due", which the planner reads as high priority). Once the AI makes the plan, those to-dos leave the inbox. Manual mode keeps them.
- **Routine on/off** (Settings → My routine → "Follow a routine"): off = no routine, e.g. holidays. Tasks go anywhere 8 AM–11 PM around Calendar events, with no school. "School on weekdays" can also be turned off on its own (footer: for school holidays). Existing plans use the new setting next time they reflow.
- **Add to Calendar moved** (the floating glass bar looked out of place): it's now the last section of the plan list ("Happy with your plan? Add it now, or later…"; "✓ In Calendar" once synced; "You changed the plan since adding it" when it needs an update). Later: long-press a plan on the Plans screen → Add / Update Calendar. Auto-add in Settings still works.
- **School hours always respected**: plans made with "Ask when I'm free each time" used to drop school hours on every day of the plan, so a Goal plan's revision could land in lessons. They now keep school hours (unless school or the routine is off).
- **School timetable → Calendar** (Settings → School → Add timetable to Calendar): pick a photo or a PDF (first 2 pages). Vision's RecognizeDocumentsRequest reads the table, the on-device model turns it into lessons (and also gets the image if the model supports vision), and the student checks and edits the list (or types lessons in without Apple Intelligence). The lessons become weekly repeating events until a chosen end of term. Re-importing replaces the last timetable. Plans then avoid lessons like any Calendar event, including ones that run past normal school hours (CCAs).
  - Uses Vision, PDFKit and PhotosUI (Apple frameworks).
  - **Week A/B (odd/even)**: a toggle plus "This week is Week A / Week B". Each lesson is Every week, Week A or Week B (the AI marks them; editable). A/B lessons repeat every 2 weeks starting in the right week, titled e.g. "Maths (Week A)".

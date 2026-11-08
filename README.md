# Canopy — Apple Device Client

Native iOS and macOS companion app for [Canopy School Planner](https://github.com/douggreenak/Canopy-School-Planner). Built entirely in SwiftUI, it gives students a fast, polished way to view their schedule, grades, homework, and tasks from any Apple device.

The backend is a Next.js web app deployed at [canopy.apexengineeringak.com](https://canopy.apexengineeringak.com). This client talks to it over a REST API using your existing Canopy account.

---

## Features

Feature-for-feature parity with the web app, in a native SwiftUI shell.

- **Dashboard** — date navigation (day / week / year stepping), tappable summary cards (classes today, upcoming homework, upcoming exams, due today), an embedded Day / Week / Year / Heatmap calendar, upcoming homework and exams, pending tasks, and banners for "Ask" tasks, schedule disruptions and PowerSchool login failures
- **Schedule** — day grid with dynamic hour bounds and hour labels, 7-day week grid, Monday-first year view, due-count badges, a date-specific class detail sheet (adjusted times, cancellations, AP chip, jump to grades), and the full Disruptions calendar (early out, late start, no school, assembly, 1-6, day swap, custom) with auto-generated period overrides and drag-to-move
- **Grades** — PowerSchool classes only; stat strip, grade overview, coming-up panel, missing-work grade impact, per-class detail with category breakdown, grade-change driver, quick filters, search and sort, assignment grade simulator, what-if calculator, final-exam calculator, transcript (unweighted + AP-weighted GPA) and the sync log
- **Planner** — unified homework + tasks with quick-add per class, in-class / after-class timing, "class cancelled" warnings, overdue styling, completion stages, rebalancing hints, delete with undo, and batch clear-done
- **Classes & Exams** — roster cards with drag reorder, school filter, roster sheet, AP detection, grade-weight editor; exams with upcoming / past tabs, class-derived times and grade-stakes framing
- **PowerSchool** — asynchronous background sync with status polling, the sync reminder sheet, scheduled-sync toggle, resume-in-flight, other-schools accounts, and the 5-step setup wizard (bell schedule, verify-then-sync, school breaks)
- **Settings** — 8 named accent presets with light/dark calibration, theme, school info, bell schedule and early-dismissal editor, lunch times, calendar feed (webcal subscribe), password change, account deletion, keyboard shortcuts (⌘1–⌘7, ⌘/) and an admin dashboard for admin accounts

## Tech Stack

| | |
|---|---|
| Language | Swift 5 |
| UI | SwiftUI |
| State | `@Observable` (Swift observation framework) |
| Networking | `URLSession` — no third-party dependencies |
| Platforms | iOS 26.5+, macOS 26.5+ |
| Backend | Canopy School Planner REST API |

The app has zero third-party Swift dependencies. All networking, persistence, and state management is handled with first-party Apple frameworks.

---

## Architecture

```
Canopy/
├── APIClient.swift            # URLSession REST client — every endpoint, NetworkActivity for the save indicator
├── AuthStore.swift            # Login / session / logout state (@Observable)
├── CanopyStore.swift          # App-wide data store + buildDaySchedule port (dayEntries) + optimistic mutations
├── PowerSchoolSyncStore.swift # Background-sync status poller (web powerschoolStatusStore / powerschoolClient)
├── Navigation.swift           # AppTab + AppNavigation (cross-tab jumps)
├── Models.swift               # Codable models matching the web API schema
├── Theme.swift                # Named accent presets (light/dark calibrations)
├── GradeEngine.swift          # Grade math: category matching, what-if, predictGradeChange, GPA points
├── GradesUtil.swift           # Status predicates, colours, letters, time buckets
├── HeatmapEngine.swift        # 14-day workload heatmap, rebalancing, due-count badges
├── ScheduleEngine.swift       # Disruption types, override generators, Lathrop templates, grid bounds
├── ContentView.swift          # Root view — splash, auth gate, admin routing, tab bar
├── Extensions/Color+Hex.swift # Shared components: chips, toast, glass cards, save indicator
└── Views/                     # One file per screen or sheet (see file names)
```

`CanopyStore` is the single source of truth, injected via `@Environment`. `PowerSchoolSyncStore` is the one poller for `/api/powerschool/status`, so any screen can show "syncing" state.

### Local testing

For simulator testing against a local backend instead of production, set the `canopyBaseURL` user default before launching:

```bash
xcrun simctl spawn booted defaults write douggreenak.Canopy canopyBaseURL http://localhost:3000
```

## Getting Started

### Requirements

- Xcode 26 or later
- A Canopy account at [canopy.apexengineeringak.com](https://canopy.apexengineeringak.com)

### Build

1. Clone the repo
2. Open `Canopy.xcodeproj` in Xcode
3. Select the **Canopy** scheme and your target device or simulator
4. Build and run (`Cmd+R`)

No package resolution or API key setup is needed — the backend URL is baked into `APIClient.swift`.

### Run on macOS

Select `My Mac` as the destination. The app runs natively on macOS using the same SwiftUI codebase. iOS-only APIs (wheel pickers, navigation bar display mode) are guarded with `#if !os(macOS)` or cross-platform extension helpers in `Color+Hex.swift`.

---

## Backend

The server is the companion [Canopy School Planner](https://github.com/douggreenak/Canopy-School-Planner) web app — a Next.js 16 / TypeScript application backed by Neon PostgreSQL. It exposes a JSON REST API at `/api/*` that this client consumes.

To point the app at a different backend (local dev, self-hosted), change the `baseURL` in `APIClient.swift`:

```swift
private let baseURL = "https://canopy.apexengineeringak.com"
```

---

## Related

- [Canopy School Planner (web)](https://github.com/douggreenak/Canopy-School-Planner) — the Next.js backend and web UI

# Canopy — Apple Device Client

Native iOS and macOS companion app for [Canopy School Planner](https://github.com/douggreenak/Canopy-School-Planner). Built entirely in SwiftUI, it gives students a fast, polished way to view their schedule, grades, homework, and tasks from any Apple device.

The backend is a Next.js web app deployed at [canopy.apexengineeringak.com](https://canopy.apexengineeringak.com). This client talks to it over a REST API using your existing Canopy account.

---

## Features

- **Dashboard** — summary cards for today's classes, upcoming homework, exams, and pending tasks; quick-look banners for schedule disruptions and items flagged to ask about
- **Schedule** — day and week calendar views with class blocks, lunch blocks, and a live now-indicator; supports schedule disruptions (early dismissals, cancelled days)
- **Grades** — adaptive card grid showing letter grades and percentages synced from PowerSchool; per-class detail with assignment list, missing/late flags, and manual homework
- **Homework & Tasks** — unified list combining homework assignments and tasks, grouped by due date with filter tabs (Upcoming / Done / All), quick-add chips by class, and swipe actions
- **Tasks** — standalone task manager with categories, priorities, due dates, and class association
- **Settings** — school info editor, native time-picker lunch schedule editor, class/exam/disruption management, appearance (dark / light / system), and account management

---

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
├── APIClient.swift          # URLSession REST client — all endpoint calls
├── AuthStore.swift          # Login / session / logout state (@Observable)
├── CanopyStore.swift        # App-wide data store — classes, homework, grades, tasks (@Observable)
├── Models.swift             # Codable model types matching the web API schema
├── ContentView.swift        # Root view — splash, auth gate, tab bar
├── Extensions/
│   └── Color+Hex.swift      # Shared components: GlassCard, AnimatedCheckButton,
│                            #   CategoryBadge, PriorityPill, FormEditCard, CanopyBackground
└── Views/
    ├── DashboardView.swift
    ├── ScheduleView.swift
    ├── GradesView.swift
    ├── HomeworkView.swift
    ├── TasksView.swift
    ├── SettingsView.swift
    ├── ManageClassesView.swift
    ├── ManageExamsView.swift
    └── ManageDisruptionsView.swift
```

`CanopyStore` is the single source of truth. It is injected at the top of the view hierarchy via `@Environment` and accessed throughout the tree without prop-drilling.

---

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

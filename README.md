# Chrono — Flutter app

Native mobile app (Android + iOS) for the Chrono AI scheduler, built from
`CHRONO.fig` (16 screens). Flutter 3.41 / Dart 3.11. The only package is `google_fonts`
(Poppins).

## Run

```powershell
flutter pub get
flutter emulators --launch Pixel_8
flutter run
```

Or plug in an Android phone with USB debugging on and run `flutter run`.
Build an installable APK with `flutter build apk --release`
(output: `build/app/outputs/flutter-apk/app-release.apk`).

**Demo shortcut:** long-press the **Chrono** tab to jump to any screen or reset the demo data.

## Screens

| Figma screen | File |
| --- | --- |
| Welcome, class schedule (choose / reading / found), preferences, building | `lib/screens/onboarding.dart` |
| Home | `lib/screens/home.dart` |
| Today / other days timeline, now line, free slots | `lib/screens/today.dart` |
| Chat (empty, proposed changes, applied) | `lib/screens/chat.dart` |
| Deadlines (upcoming / done) | `lib/screens/deadlines.dart` |
| Tab bar, toast, block bottom sheet, demo menu | `lib/screens/app_shell.dart` |

## Structure

- `lib/theme/tokens.dart` — colours, kind colours and type helper, taken from the Figma variables.
- `lib/data/models.dart` — models plus seed data from the design. The demo clock is fixed at
  Thursday 15 Oct, 10:40.
- `lib/state/app_state.dart` — one `ChangeNotifier` with every action; widgets read it through `AppScope`.
- `lib/logic/chrono_engine.dart` — rule-based stand-in for the AI. It handles "Org meeting at 3pm for 1h",
  "Skip gym today", "I'm sick, clear my afternoon", "Add Stats quiz due Monday, 3h",
  "Plan time for …", "Move … " and "How does my day look?". To go live, replace `respond()` with a
  call to your backend/LLM that returns the same `Reply(text, changes)`.
- `lib/logic/time_utils.dart` — free-time and slot-finding helpers.

Data is held in memory, so restarting the app resets the demo.

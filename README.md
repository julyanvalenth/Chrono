# Chrono — Flutter app

Native mobile app (Android + iOS) for the Chrono AI scheduler, built from
`CHRONO.fig` (16 screens). Flutter 3.50 / Dart 3.14. Packages: `google_fonts`
(Poppins), `http`, `shared_preferences`, `image_picker`.

## Run

```powershell
flutter pub get
flutter emulators --launch Medium_Phone_API_36.1
flutter run
```

Or plug in an Android phone with USB debugging on and run `flutter run`.
Build an installable APK with `flutter build apk --release`
(output: `build/app/outputs/flutter-apk/app-release.apk`).

In Android Studio the project needs the **Flutter** and **Dart** plugins (the Flutter
plugin installs Dart with it) plus the Flutter SDK path set to `C:\src\flutter`.
Without them Studio treats the folder as a plain Java module and offers no Run
configuration.

**Demo shortcut:** long-press the **Chrono** tab to jump to any screen or reset the demo data.

## Screens

| Figma screen | File |
| --- | --- |
| Welcome, class schedule (choose / reading / found), preferences, building | `lib/screens/onboarding.dart` |
| Sign up / log in | `lib/screens/auth.dart` |
| Home | `lib/screens/home.dart` |
| Today / other days timeline, now line, free slots | `lib/screens/today.dart` |
| Chat (empty, proposed changes, applied) | `lib/screens/chat.dart` |
| Deadlines (upcoming / done) | `lib/screens/deadlines.dart` |
| Profile (name, work preferences, log out) | `lib/screens/profile.dart` |
| Tab bar, toast, block bottom sheet, demo menu | `lib/screens/app_shell.dart` |

## Structure

- `lib/theme/tokens.dart` — colours, kind colours and type helper, taken from the Figma variables.
- `lib/data/models.dart` — models plus seed data from the design. The schedule is a weekly
  template (day 0 = Monday); `today`, `now` and `days` follow the device's real clock and dates.
  The backend uses its own clock with the device's UTC offset (`?tz_offset=`), so both agree.
- `lib/state/app_state.dart` — one `ChangeNotifier` with every action; widgets read it through `AppScope`.
- `lib/logic/chrono_engine.dart` — rule-based stand-in for the AI. It handles "Org meeting at 3pm for 1h",
  "Skip gym today", "I'm sick, clear my afternoon", "Add Stats quiz due Monday, 3h",
  "Plan time for …", "Move … " and "How does my day look?". To go live, replace `respond()` with a
  call to your backend/LLM that returns the same `Reply(text, changes)`.
- `lib/logic/time_utils.dart` — free-time and slot-finding helpers.
- `lib/logic/suggestions.dart` — builds the Home and Chat shortcut chips from today's blocks,
  open deadlines, focus window and bedtime.

With the backend running the schedule lives in Supabase, so it survives a restart. Without
it the app keeps the in-memory state and falls back to the rule-based engine.

## App icon & splash

The launcher icon and the launch (splash) screen use the Chrono mark on `#121116`.
Source images live in `assets/branding/` and are drawn by `tool/make_brand_assets.py`
(same shape and colours as `lib/widgets/chrono_mark.dart`). After changing them:

```powershell
python tool/make_brand_assets.py
dart run flutter_launcher_icons
dart run flutter_native_splash:create
```

While the app signs in and loads the schedule it shows the same logo (`_Loading` in `app_shell.dart`),
so the native splash hands over without a jump.

## Deploy

Backend on Vercel, Android APK on GitHub Releases (built by GitHub Actions): see [DEPLOY.md](DEPLOY.md).

## Backend (Supabase + Gemini)

The backend is in [`backend/`](backend/README.md) (Express + Supabase + Gemini). Start it first, then run the app:

```powershell
cd backend
npm install      # first time only
npm run dev      # http://localhost:3000
```

Then `flutter run` from the repo root. Supabase and Gemini setup: [`backend/chrono-backend-guide.md`](backend/chrono-backend-guide.md).
`backend/.env` holds the keys and is git-ignored. Copy `backend/.env.example` to start.

Database scripts, run in this order in the Supabase SQL editor:

1. `backend/supabase-schema.sql` — tables, indexes and RLS policies.
2. `backend/supabase-grants.sql` — grants for `anon`, `authenticated` and `service_role`.
3. `backend/supabase-reset.sql` — only when the schema drifted and you are fine dropping
   the Chrono tables and starting clean.

- Android emulator reaches the backend at `http://10.0.2.2:3000` (default).
- Windows / web / iOS simulator use `http://localhost:3000`.
- A real phone on the same Wi-Fi: `flutter run --dart-define=CHRONO_API_URL=http://<your-PC-IP>:3000`.

Users sign up or log in with email + password (`lib/screens/auth.dart`, Supabase Auth through the backend).
The session (access + refresh token, never the password) is kept on the device, so the app opens straight
to the schedule next time; tapping the avatar opens the profile (name, work preferences, log out).
Onboarding, block actions, deadlines, chat and Undo are saved to Supabase; chat replies come from Gemini.
If the backend can't be reached the app keeps working offline with the built-in rule-based engine.
`lib/services/api_client.dart` holds the HTTP client and JSON mapping.

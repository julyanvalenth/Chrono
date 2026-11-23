# Chrono Backend

Node.js/Express API backend for the Chrono AI scheduler mobile app.

## Stack

- **Runtime:** Node.js (ES modules)
- **Framework:** Express
- **Database & Auth:** Supabase (PostgreSQL + built-in auth)
- **AI:** Google Gemini API (gemini-2.0-flash)

## Setup

### 1. Create a Supabase project

1. Go to [supabase.com](https://supabase.com) and create a new project.
2. Open the **SQL Editor** and run the contents of `supabase-schema.sql`.
3. Copy your project URL, anon key, and service role key from **Settings → API**.

### 2. Get a Gemini API key

1. Go to [aistudio.google.com](https://aistudio.google.com/apikey) and create an API key.

### 3. Configure environment

```bash
cp .env.example .env
```

Fill in your keys in `.env`:

```
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_ANON_KEY=your-anon-key
SUPABASE_SERVICE_KEY=your-service-role-key
GEMINI_API_KEY=your-gemini-api-key
PORT=3000
```

### 4. Install & run

```bash
npm install
npm run dev    # dev mode with auto-reload
# or
npm start      # production
```

## API Endpoints

### Auth (no token required)

| Method | Endpoint | Body | Description |
|--------|----------|------|-------------|
| POST | `/api/auth/signup` | `{ email, password, name? }` | Register a new user |
| POST | `/api/auth/login` | `{ email, password }` | Sign in, get token |
| POST | `/api/auth/refresh` | `{ refresh_token }` | Refresh access token |

### Blocks (requires `Authorization: Bearer <token>`)

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/api/blocks?day=3` | List blocks (optionally filter by day) |
| POST | `/api/blocks` | Create a block |
| PUT | `/api/blocks/:id` | Update a block |
| DELETE | `/api/blocks/:id` | Delete a block |
| POST | `/api/blocks/:id/done` | Toggle done |
| POST | `/api/blocks/:id/push` | Push by N minutes `{ minutes: 30 }` |

### Courses

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/api/courses` | List all courses |
| POST | `/api/courses` | Create a course |
| PUT | `/api/courses/:id` | Update a course |
| DELETE | `/api/courses/:id` | Delete a course |
| POST | `/api/courses/:id/toggle` | Toggle selected |
| POST | `/api/courses/generate-blocks` | Regenerate lecture blocks from selected courses |

### Deadlines

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/api/deadlines` | List all deadlines |
| POST | `/api/deadlines` | Create a deadline |
| PUT | `/api/deadlines/:id` | Update a deadline |
| DELETE | `/api/deadlines/:id` | Delete a deadline |
| POST | `/api/deadlines/:id/toggle` | Toggle done |

### Preferences

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/api/preferences` | Get user preferences |
| PUT | `/api/preferences` | Update preferences |

### Chat (AI — the core feature)

| Method | Endpoint | Body | Description |
|--------|----------|------|-------------|
| GET | `/api/chat` | — | Get message history |
| POST | `/api/chat?tz=Asia/Jakarta` | `{ message }` | Send message, get AI response with proposed changes |
| POST | `/api/chat/:id/apply` | — | Apply a proposal's changes to the schedule |
| POST | `/api/chat/:id/dismiss` | — | Dismiss a proposal |
| DELETE | `/api/chat` | — | Clear chat history |

### Other

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/api/health` | Health check |

## How the AI Chat Works

1. Client sends `POST /api/chat` with the user's message (e.g. "Org meeting at 3pm for 1h").
2. Server fetches the user's current blocks, deadlines, and preferences from Supabase.
3. Server builds a schedule context and sends it to Gemini with a structured prompt.
4. Gemini returns JSON with a text response and proposed changes (add/move/remove blocks).
5. Server validates the changes and saves everything to the database.
6. Client receives the AI response + proposal. User can then call `/apply` or `/dismiss`.

## Connecting from Flutter

In the Flutter app, replace the local `respond()` call in `app_state.dart` with an HTTP call to `POST /api/chat`. The response maps directly to the existing `Reply`, `Change`, `AddChange`, `MoveChange`, and `RemoveChange` classes.

## Changes for the Flutter app (Nov 2026)

- **Gemini models:** `gemini-2.0-flash` / `gemini-2.5-flash` are retired. The server now tries the
  models in `GEMINI_MODEL` (comma-separated) in order, moving on when one returns 503/429/404 or times out.
- **Supabase clients:** sign-in/refresh use a separate anon client, so the service-role client never
  picks up a user session (before, after the first login every DB query ran as that user).
- **Express 5:** async errors reach the error handler instead of hanging the request.
- `POST /api/chat` accepts `?day=3&now=640` so the AI uses the app's clock (the app's demo clock).
- `POST /api/chat/:id/apply` now also returns `added_ids` and `deadlines`, and clears old `origin` flags correctly.
- AI changes are validated harder: bad times, unknown IDs, lectures, and clashes with a class are dropped.
- `GET /api/health` shows whether the database and AI are configured; other routes return 503 until Supabase is.

### New endpoints

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/api/me` | Preferences, courses, blocks, deadlines and chat in one call |
| POST | `/api/me/onboarding` | Save onboarding: `{ preferences, courses[], blocks[], deadlines[] }` (builds lecture blocks) |
| DELETE | `/api/me/data` | Clear the user's data (demo reset) |
| POST | `/api/blocks/replace` | Replace all blocks `{ blocks[] }` (Undo) |
| POST | `/api/deadlines/replace` | Replace all deadlines `{ deadlines[] }` (Undo) |
| POST | `/api/schedule/parse` | Read a timetable with Gemini: `{ image: <base64>, mime_type }` (KRS screenshot/photo) or `{ text }`. Returns `{ courses: [{ code, name, days[], start_min, end_min, room }], note }`. Saves nothing — the app sends the chosen courses with `/api/me/onboarding`. |

Try it: `node scripts/schedule-test.mjs path/to/timetable.jpg` (server must be running).

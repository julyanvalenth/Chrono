# Deploying Chrono

Two pieces go online:

| Piece | Where | Updates |
|---|---|---|
| Backend API (`backend/`) | **Vercel** (free), connected to this GitHub repo | Every push to `main` redeploys it |
| Android app | **GitHub Releases** — an `.apk` built by GitHub Actions | Every tag `v*` publishes a new Release |

Everyone shares the same Supabase database and Gemini key through the backend;
each person signs up with their own account in the app.

---

## 1. Backend on Vercel (one time)

1. Go to [vercel.com](https://vercel.com) → **Sign Up / Log in with GitHub**.
2. **Add New… → Project** → import **`julyanvalenth/Chrono`**
   (grant Vercel access to the repo if asked).
3. Configure the project:
   - **Root Directory:** `backend`  ← important
   - **Framework Preset:** Other
   - Build / Output settings: leave empty
4. **Environment Variables** — copy them from your local `backend/.env`:

   | Name | Value |
   |---|---|
   | `SUPABASE_URL` | your Supabase project URL |
   | `SUPABASE_ANON_KEY` | publishable key (`sb_publishable_…`) |
   | `SUPABASE_SERVICE_KEY` | secret key (`sb_secret_…`) — keep private |
   | `GEMINI_API_KEY` | your Gemini key |
   | `GEMINI_MODEL` | `gemini-flash-lite-latest,gemini-3-flash-preview,gemini-3.8-flash,gemini-flash-latest` |

5. **Deploy**. When it's done, copy the domain (e.g. `https://chrono-xxxx.vercel.app`) and open
   `https://<your-domain>/api/health` — it should say `"database": "configured"` and list the Gemini models.

How it runs: `backend/api/index.js` exposes the Express app (`backend/app.js`) as one serverless
function; `backend/vercel.json` sends every path to it and allows up to 60 s per request (AI calls).
Request bodies are limited to 4.5 MB on Vercel, so timetable images are capped at 3 MB (the app
already shrinks photos before uploading).

## 2. Point the app at the backend

The backend URL is compiled into the APK. Set it once, either:

- edit `CHRONO_API_URL` near the top of `.github/workflows/android-release.yml`, or
- GitHub → repo **Settings → Secrets and variables → Actions → Variables** → add
  `CHRONO_API_URL` = `https://<your-domain>` (no trailing slash). This overrides the file.

## 3. Publish an APK release

```powershell
git tag v1.0.0
git push origin v1.0.0
```

GitHub Actions (**Actions** tab → *Android release*) builds the APK in ~10 minutes and creates the
Release **v1.0.0** with `chrono-v1.0.0.apk`. Share the Releases page link:
`https://github.com/julyanvalenth/Chrono/releases/latest`.

Bump `version:` in `pubspec.yaml` (e.g. `1.0.1+2`) before tagging the next release.

To just test a build without making a Release: **Actions → Android release → Run workflow**;
the APK is attached to that run under *Artifacts*.

## 4. (Recommended) A permanent signing key

Without it, each CI build is signed with a new throwaway key, so testers must **uninstall the old
version before installing a new one**. To keep one signature:

```powershell
# Creates upload-keystore.jks — keep this file and its passwords safe and private.
keytool -genkey -v -keystore upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
[Convert]::ToBase64String([IO.File]::ReadAllBytes("upload-keystore.jks")) | Set-Clipboard
```

Then add repository **Secrets** (Settings → Secrets and variables → Actions → Secrets):
`ANDROID_KEYSTORE_BASE64` (paste from clipboard), `ANDROID_KEYSTORE_PASSWORD`,
`ANDROID_KEY_ALIAS` (`upload`), `ANDROID_KEY_PASSWORD`. Never commit the `.jks` file.

## Installing (for testers)

1. On the Android phone, open the Releases page and download `chrono-vX.Y.Z.apk`.
2. Open it; allow **Install unknown apps** for the browser when Android asks.
3. Open Chrono → **Get started** → create an account.

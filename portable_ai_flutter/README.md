# Portable AI – Flutter starter

## Included
- Dark Android UI with Chat, Image Studio and Video Studio tabs.
- Chat: OpenAI-compatible Chat Completions API in online mode; simple local fallback responses offline.
- Image Studio: pick a gallery image and apply on-device grayscale or sepia effects.
- Image Studio has a configurable backend endpoint for AI image creation/editing. The backend must accept multipart `prompt` and optional `image`, and return JSON with `image_url` or `image_base64`.
- Video Studio: pick a gallery video and preview/play it.

## Honest feature limits
- Offline chat is **not** a full local language model. A local inference engine and model file still need to be integrated.
- Local image effects work offline. Generative image editing is wired to a configurable backend contract, but no backend is supplied or hosted in this source package; you must deploy one before the AI button can work.
- Video Studio currently selects and plays videos; AI video editing/generation is not connected.
- The online chat API key is kept in memory only by this starter app. For a public release, route API calls through a secure backend; never ship a private provider key in a public APK.
- API use may incur charges.

## Build on GitHub from an Android phone
1. Download and extract this ZIP.
2. Create a GitHub repository, e.g. `portable-ai`.
3. Upload all extracted files and folders, including the hidden `.github` folder. If mobile upload hides dot-folders, create `.github/workflows/android-apk.yml` in GitHub's web editor and paste the workflow below.
4. Open **Actions** and run **Build Android APK**.
5. Download `portable-ai-apk` from the successful workflow run's Artifacts.

## Build locally
Install Flutter and Android SDK, then run:
```bash
flutter create . --platforms=android --project-name portable_ai
flutter pub get
flutter build apk --release
```
APK: `build/app/outputs/flutter-apk/app-release.apk`

## Android permissions
The `image_picker` and `video_player` plugins manage the required media access flow. No broad storage permission is requested by this app.

## Backend contract reminder
The image and video endpoints in the app are generic client integrations, not hosted AI providers. Your server must implement the documented multipart request/JSON response contract. Keep provider credentials on the server, authenticate app requests, validate uploads, and use HTTPS.

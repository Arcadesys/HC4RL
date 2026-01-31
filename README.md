# HC4RL

Low vision assistive tools suite: edge highlight, region zoom, and face & names — in a single app.

## Setup

1. **Flutter**: Ensure Flutter is installed and on your PATH.

2. **Regenerate platform files** (if you cloned or created the project without `flutter create`):
   ```bash
   flutter create .
   ```
   This restores/updates `android/` (including Gradle wrapper) and `ios/` (Xcode project).

3. **Dependencies**:
   ```bash
   flutter pub get
   ```

4. **Run**:
   ```bash
   flutter run
   ```

## Tools

- **Edge Highlight** — Real-time Canny edge overlay on the camera for low-light visibility.
- **Region Zoom** — Zoom into the center of the camera view (slider 1×–4×).
- **Face & Names** — Add people (photo + name); when the camera sees them, their name is shown on screen.

## Architecture

- **Shell**: Tool picker (home) → tap a tool → tool screen; back returns to picker.
- **Shared**: Camera service, `CameraImage` converter (grayscale/RGB), permissions.
- **Per-tool**: Each tool under `lib/tools/<id>/` (edge, region_zoom, face_names).

See [AGENTS.md](AGENTS.md) for constraints and implementation details.

## Pipeline to Android

**Local build**

1. One-time: ensure Android has Gradle wrapper and `local.properties`:
   ```bash
   flutter create . --project-name hc4rl --org xyz.hc4rl
   flutter pub get
   ```
2. Build release APK:
   ```bash
   flutter build apk --release
   ```
   Output: `build/app/outputs/flutter-apk/app-release.apk`.

**CI (GitHub Actions)**

- Workflow: [.github/workflows/android.yml](.github/workflows/android.yml)
- Runs on push/PR to `main` or `master`, and on manual trigger.
- Steps: checkout → Flutter setup → `flutter create .` → `flutter pub get` → `flutter analyze` → `flutter build apk --release`.
- The built APK is uploaded as an artifact named `app-release`; download it from the run’s **Artifacts** in the Actions tab.

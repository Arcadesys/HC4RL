# Getting started: Android app development & deploy to phone

Deploy the HC4RL Flutter app to your connected Android phone.

---

## Fix “flutter doctor” Android issues only

If `flutter doctor` shows **Android** with:

- **cmdline-tools component is missing**
- **Android license status unknown**

you only need to fix the Android toolchain. **Xcode**, **CocoaPods**, and **Chrome** are optional for Android; you can ignore those for now.

### 1. Install Android cmdline-tools

**Option A — Via Android Studio (easiest)**

1. Open **Android Studio**.
2. **Settings** (or **Android Studio** → **Preferences** on macOS) → **Languages & Frameworks** → **Android SDK**.
3. Open the **SDK Tools** tab.
4. Enable **Android SDK Command-line Tools (latest)**.
5. Click **Apply** / **OK** and let it install.

To run Android Studio from the terminal (`studio`), add to `~/.zshrc`:

```bash
export PATH="$PATH:/Applications/Android Studio.app/Contents/MacOS"
```

Then `source ~/.zshrc` (or open a new terminal) and run `studio` to launch Android Studio.

**Option B — Command-line tools only (no Android Studio)**

1. Create SDK dir: `mkdir -p $HOME/Library/Android/sdk/cmdline-tools`.
2. Download **Command line tools only** for Mac:  
   https://developer.android.com/studio#command-line-tools-only  
   (e.g. `commandlinetools-mac-*_latest.zip`).
3. Unzip; you get a folder `cmdline-tools`. Rename it to `latest` and move it so the path is:
   `$HOME/Library/Android/sdk/cmdline-tools/latest`.
4. Set env (add to `~/.zshrc`):
   ```bash
   export ANDROID_HOME=$HOME/Library/Android/sdk
   export PATH="$PATH:$ANDROID_HOME/platform-tools:$ANDROID_HOME/cmdline-tools/latest/bin:/Applications/Android Studio.app/Contents/MacOS"
   ```
5. Install platform-tools and a platform:
   ```bash
   source ~/.zshrc
   sdkmanager "platform-tools" "platforms;android-34"
   ```

### 2. Accept Android licenses

```bash
flutter doctor --android-licenses
```

Type `y` for each prompt. If it says `ANDROID_HOME` is not set, add the two `export` lines above to `~/.zshrc` and run `source ~/.zshrc`, then try again.

### 3. Verify

```bash
flutter doctor -v
```

The **Android toolchain** line should show **[✓]** with no cmdline-tools or license errors.

---

## 1. Install Flutter (one-time)

**Option A — Homebrew (recommended on macOS)**

```bash
brew install --cask flutter
```

Then add Flutter to your shell (add to `~/.zshrc` if you use zsh):

```bash
export PATH="$PATH:/opt/homebrew/Caskroom/flutter/*/flutter/bin"
# or after install, run: flutter precache && which flutter
```

**Option B — Manual**

1. Download the SDK: https://docs.flutter.dev/get-started/install/macos  
2. Extract to e.g. `~/development/flutter`  
3. Add to PATH in `~/.zshrc`:
   ```bash
   export PATH="$PATH:$HOME/development/flutter/bin"
   ```

Verify:

```bash
flutter doctor
```

---

## 2. Install Android toolchain (one-time)

Flutter needs the Android SDK and `adb` to talk to your phone.

**Option A — Android Studio (easiest)**

1. Install: https://developer.android.com/studio  
2. Open Android Studio → **More Actions** → **SDK Manager**.  
3. Install **Android SDK Platform** (e.g. latest API level) and **Android SDK Command-line Tools**.  
4. Accept the Android SDK license (see below).

**Option B — Command-line only**

1. Install Android command-line tools: https://developer.android.com/studio#command-tools  
2. Use `sdkmanager` to install `platform-tools` and a platform (e.g. `platforms;android-34`).

**Accept licenses**

```bash
flutter doctor --android-licenses
```

Answer `y` to all. Fix any “ANDROID_HOME not set” by adding to `~/.zshrc`:

```bash
export ANDROID_HOME=$HOME/Library/Android/sdk
export PATH="$PATH:$ANDROID_HOME/platform-tools:$ANDROID_HOME/cmdline-tools/latest/bin"
```

Then:

```bash
source ~/.zshrc
flutter doctor -v
```

You want **Android toolchain** and **Android Studio** (or **VS Code**) to show as OK.

---

## 3. Prepare your Android phone

1. **Enable Developer options**  
   Settings → About phone → tap **Build number** 7 times.

2. **Enable USB debugging**  
   Settings → System → Developer options → **USB debugging** ON.

3. **Connect the phone**  
   Use a data-capable USB cable (not charge-only).

4. **Trust this computer**  
   On the phone, when prompted “Allow USB debugging?”, check **Always allow** and tap **Allow**.

5. **Unlock the phone**  
   Keep the screen unlocked the first time you run the app (some devices require this).

---

## 4. Ninja and CMake (required for opencv_dart / dartcv4 native build)

This project uses **opencv_dart**, which builds native code and needs **Ninja** and **CMake** on your PATH. If the build fails with `Failed to find ninja version: latest` or `Failed to find cmake with version=latest`, install both:

```bash
brew install ninja cmake
```

Then run `flutter run` again.

---

## 5. Deploy the app to your phone

In the project directory:

```bash
cd /Users/austen/code/HC4RL

# Fetch dependencies
flutter pub get

# See connected devices (your phone should appear)
flutter devices

# Run on the connected Android device (debug build)
flutter run
```

To pick a specific device if several are connected:

```bash
flutter run -d <device-id>
```

Example: `flutter run -d emulator-5554` or `flutter run -d <your-phone-id>`.

**First run:** The app will install and open on the phone. You may need to grant **Camera** when the app asks.

---

## 6. Build a release APK (optional)

To build an APK you can share or install without a computer:

```bash
flutter build apk --release
```

APK path: `build/app/outputs/flutter-apk/app-release.apk`.  
Copy to the phone (e.g. Google Drive, USB) and install (you may need “Install from unknown sources” enabled for the file manager).

---

## Quick checklist

| Step                         | Command / action                          |
|-----------------------------|-------------------------------------------|
| Flutter on PATH             | `which flutter` → path shown              |
| Android licenses            | `flutter doctor --android-licenses`       |
| Environment                 | `flutter doctor -v` → no red errors       |
| Phone connected             | `flutter devices` → device listed         |
| Deploy                      | `flutter run`                             |

---

## Troubleshooting

- **“No devices found”**  
  Replug USB, unlock phone, accept “Allow USB debugging”, run `flutter devices` again. On macOS, avoid USB hubs for first connection.

- **“ANDROID_HOME not set”**  
  Set `ANDROID_HOME` and add `platform-tools` to `PATH` (see step 2), then `source ~/.zshrc`.

- **“Camera” or “Permission denied”**  
  In app, grant Camera when prompted, or in Settings → Apps → HC4RL → Permissions.

- **Build errors**  
  Run `flutter clean && flutter pub get` then `flutter run` again.

- **“Failed to find ninja version: latest”** or **“Failed to find cmake with version=latest”**  
  The opencv_dart dependency (dartcv4) needs Ninja and CMake to build native code. Install both: `brew install ninja cmake`, then run `flutter run` again.

- **“The getter 'isStreamingImagesSupported' isn't defined for the type 'CameraValue'”**  
  Use the controller method instead: `controller.supportsImageStreaming()` (already fixed in this project).

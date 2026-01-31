# Edge detection crash & overflow fix plan

From terminal log when starting Edge Highlight:

1. **RenderFlex overflow** – Tool picker `Column` overflowed by 18px (tool_picker_screen.dart:54).
2. **SIGSEGV in libdartcv.so** – `cv_Mat_get_i32_3` crash when reading `findNonZero` result in edge_detector_service (opencv_dart native code).
3. **Main-thread overload** – "Skipped 624 frames" / "Skipped 60 frames" and long frame times.

(An earlier run also showed `CoverController` / `MethodChannel.setMethodCallHandler` before `WidgetsFlutterBinding.ensureInitialized()`; that code is not in the current repo but any new platform channel must run after `WidgetsFlutterBinding.ensureInitialized()`.)

---

## 1. Fix tool picker overflow

**Cause:** GridView gives each card a fixed size (~125×125 px). The card’s `Column` (icon 48, spacing 12, text) can exceed that on small or high-density screens.

**Fix:** Make the card content scale to fit inside the card (e.g. wrap the `Column` in `FittedBox` with `BoxFit.scaleDown`) so it never overflows. Optionally use `overflow: TextOverflow.ellipsis` and `maxLines: 2` on the label.

**File:** `lib/shell/tool_picker_screen.dart`.

---

## 2. Fix SIGSEGV in edge detection (findNonZero → atI32)

**Cause:** After `cv.findNonZero(edges)`, we read points with `nonzero.atI32(r, i1: 0, i2: 0)` and `atI32(r, i1: 0, i2: 1)`. The native `cv_Mat_get_i32_3` is crashing (likely bad ref, layout, or threading on this device).

**Fix:** Avoid the native `atI32` path by reading the `findNonZero` result from the Mat’s raw buffer:

- `findNonZero` returns N×1 CV_32SC2: each row is one point (x, y).
- Use `Mat.data` (or equivalent) to get a `Uint8List`, then interpret it as `Int32List`: for row `r`, `x = list[2*r]`, `y = list[2*r+1]`, with bounds `r < min(nonzero.rows, list.length ~/ 8)` (or `rows * 2` for int32 count).

**File:** `lib/tools/edge/edge_detector_service.dart`.

**Fallback:** If `Mat.data` is unavailable or step is non-contiguous, wrap the existing `atI32` loop in try/catch and return empty points on exception so the app doesn’t crash (and consider reporting the issue to opencv_dart).

---

## 3. Binding / CoverController

**Current repo:** No `CoverController` or early `MethodChannel`. If you reintroduce any platform channel or singleton that calls `setMethodCallHandler` at class load time, ensure `WidgetsFlutterBinding.ensureInitialized()` is called at the very start of `main()` before any such code runs.

---

## 4. Performance and onboard AI

**Already in place:**

- Edge pipeline runs on main isolate (comment notes opencv_dart/FFI issues in `compute()` on mobile).
- `_processing` flag in edge_screen throttles to “one frame at a time” (skip while busy).

**Improvements:**

- **Frame skip:** Only feed every 2nd or 3rd camera frame to the edge pipeline (e.g. increment a counter and process only when `counter % 2 == 0`). Reduces CPU and frame drops.
- **Resolution:** Keep using `ResolutionPreset.low` and current converter; avoid increasing resolution until pipeline is stable.
- **Onboard AI / acceleration:**
  - **Edge detection:** Remain with OpenCV Canny + findNonZero (no built-in “edge” AI in the current stack). Optionally try moving the **whole** edge function to a background isolate again on a device where opencv_dart doesn’t crash (with the buffer-only copy approach above, isolate might be safer).
  - **Face & Names:** Uses TFLite (face_verification). If that runs on the same app session, consider enabling TFLite GPU delegate where supported to free CPU and reduce contention with the camera/edge path.
  - **CameraX:** Logs show CameraX with Preview + ImageCapture + ImageAnalysis. Ensure only one screen uses the camera at a time and that we don’t attach an extra ImageAnalysis for the edge tool if the Flutter `camera` plugin doesn’t require it.

---

## Implementation order

1. Fix tool picker overflow (FittedBox / text overflow).
2. Fix edge SIGSEGV by reading findNonZero from Mat buffer (Int32List) instead of atI32.
3. Add frame skip (e.g. every 2nd frame) in edge_screen.
4. (Optional) Document binding and TFLite GPU in AGENTS.md or README.

After (1) and (2), run the app, open Edge Highlight, and confirm no overflow and no crash when the first frame is processed.

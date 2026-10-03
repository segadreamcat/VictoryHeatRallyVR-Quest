# Victory Heat Rally VR: Quest Standalone

An unofficial mod that runs **Victory Heat Rally** natively on a **Meta Quest** headset in full VR. No PC, no Link cable and no streaming are needed while you play. You sit in the cockpit, grab the wheel with your Touch controllers (or steer with a thumbstick), and the rest of the game plays as normal.

This repository has **no game files**. The installer builds the Quest app on your own PC from **your own Steam copy** of the game, then installs it on your headset over USB.

> Not affiliated with or endorsed by the developers or publisher of Victory Heat Rally. Single player only.

## Features

- **Full VR racing:** a 3D cockpit with head tracking, a working dashboard, a course map and a rear-view mirror.
- **Steady frame rate:**
  - The game runs at its native 60 fps, and the headset displays at 120 Hz, so head motion stays smooth.
  - The sharpness adjusts automatically to hold 60 fps.
- **Sharp image:**
  - Renders at up to 1.2× the headset's recommended size.
  - Uses fixed foveated rendering, which renders the outer edge of the view at lower resolution.
  - Compositor sharpening is on.
  - **Lens Fit** settings match the Quest 3's off-centre lenses.
- **Two ways to steer** (Options → Controls → Steering):
  - **Virtual Wheel:** grab the cockpit wheel with the grips and turn it like a real one.
  - **Thumbstick:** steer with the left stick.
- **Rumble:** strong haptics for crashes, boosts, landings, rumble strips and wall scrapes.
- **Cockpit colours that match your car:**
  - The interior trim, the hood and the driver's gloves take on the colours of the car and paint job you pick.
  - The racing sleeves get a design that suits the colour: flames, a checkered band, a lightning bolt, stripes or chevrons.
- **Menus and messages in VR:**
  - Menus appear on a big floating screen.
  - In races, the countdown, GOAL, the pause menu and the continue screen appear on a panel in front of you.

## Requirements

- **Meta Quest 3, 3S or 2.** Quest Pro should work but runs at 90 Hz.
  - **Developer Mode** must be on. In the Meta Horizon phone app: Devices → your headset → Headset settings → Developer Mode.
- **A Windows PC** with a USB cable that carries data, for example the Link cable or the one that came with the headset.
- **Victory Heat Rally on Steam**, at the supported build. The installer checks it.
- **Python 3** from <https://www.python.org/downloads/>. Tick **"Add python.exe to PATH"** when installing.
- **UndertaleModTool CLI for Windows** from <https://github.com/UnderminersTeam/UndertaleModTool/releases>.
  - Extract the whole thing to `tools\UndertaleModCli\` so that `tools\UndertaleModCli\UndertaleModCli.exe` exists.
- **adb**, from Android SDK Platform-Tools at <https://developer.android.com/tools/releases/platform-tools>.
  - Extract it to `tools\platform-tools\`, or keep an existing Android SDK install.
- **Driver artwork:** a 1024 × 559 PNG of the hands on the wheel. This is the same file the PC VR mod uses (see *Driver artwork* below).
  - Without it the cockpit has no hands or steering wheel.

## Install

1. Download this repository: Code → Download ZIP. Extract it somewhere, such as `Documents\VictoryHeatRallyVR-Quest`.
2. Put UndertaleModCli and, if needed, platform-tools into the `tools` folder as described in Requirements.
3. Close the game. Plug in the headset, put it on, and accept **Allow USB debugging**. Tick *Always allow from this computer*.
4. Double-click **`Install-Quest.bat`**.

The installer:

1. Checks your game files.
2. Downloads the OpenXR loader from Maven Central.
3. Patches your game data for the Quest.
4. Builds and signs `VHRQuest.apk`.
5. Installs it.

The first run takes a few minutes. Then, in the headset, open **Library → Unknown Sources → VHR Quest**.

**Game in a different folder?** Run it from PowerShell:

```powershell
powershell -ExecutionPolicy Bypass -File .\Install-Quest.ps1 -GameDirectory 'D:\SteamLibrary\steamapps\common\Victory Heat Rally' -DriverArtwork 'D:\Art\VHR-driver.png'
```

Other options:

- `-BuildOnly` only builds `build\VHRQuest.apk` and doesn't install it.
- `-UndertaleModCli <path>` and `-Adb <path>` point to tools stored elsewhere.

If the PC VR mod is installed, the installer uses the original game data that mod backed up. Your PC install is not changed.

**Updating:** download the new version and run `Install-Quest.bat` again. Saves and settings stay on the headset.

## Controls

| Touch controller | Racing | Menus |
|---|---|---|
| Right trigger | Gas | Accept |
| Left trigger | Brake | |
| Grip (one or both hands) | Hold and turn the wheel (Virtual Wheel mode) | Hold + stick up/down: move the menu screen nearer or farther |
| Left thumbstick | Steer (Thumbstick mode) | Navigate |
| A / X | Drift | A = accept |
| B | Look back | Back |
| Y | | Back |
| Left menu button | Pause | Pause |
| Right stick click | Cockpit / chase camera | |
| Left stick click | Recenter | Recenter |

The game always starts on **Thumbstick** steering. You can switch to the wheel at any time in Options → Controls → Steering.

## VR options (in the game's Options menu)

| Option | Where | What it does |
|---|---|---|
| Steering | Controls | Virtual Wheel or Thumbstick |
| Lens Fit | Video | **Sharp** fits the Quest 3's off-centre lenses and is the sharpest. **Medium** and **Safe** use a centred view: softer, but a fallback if anything looks warped. |
| Foveation | Video | Off / Low / Medium / High. Higher levels use fewer pixels at the edge of the lens, which leaves room for more sharpness in the middle. |
| Cockpit Colors | Video | **Car Paint** colours the interior, gloves and sleeves to match your car. **Classic** keeps the original purple/teal. |
| Vibration | Controls | Controller rumble on or off |

## Advanced tuning

You can create `/sdcard/Android/data/com.segadreamcat.vhrquest/files/vhrq.txt` on the headset, for example with `adb push`. Put one `key=value` per line.

| Key | Default | Meaning |
|---|---|---|
| `refresh` | 120 | Highest display rate to request. At 120 Hz, each game frame is shown twice. |
| `eye_size` | auto | Largest render size per eye (auto = 1.2× recommended) |
| `dyn_res`, `eye_min` | 1, 1152 | Automatic sharpness, and the smallest size it may use |
| `haptics`, `haptic_scale` | 1, 1.6 | Rumble on/off and strength |
| `wheel_lock` | 100 | Degrees of wheel turn for full steering |
| `wheel_return` | 0.12 | Seconds for a released wheel to recentre |
| `theatre_dist`, `theatre_width` | 4.0, 3.2 | Menu screen distance and width in meters |
| `sharpen` | 1 | Compositor sharpening: 0 off, 1 normal, 2 strong |

## Bug reports

Right after a problem, with the headset plugged in, run **`Get-QuestLog.bat`**. It saves `logs\vhrq-log.txt` and `logs\vhrq-log-previous.txt`. The second one is the log from before a crash, even if you have already restarted the game.

Attach both files to an issue. The log has a `timing:` line every 3 seconds (frame rate, render size, hitches) and any game errors.

## Driver artwork

The cockpit's hands and steering wheel come from a 1024 × 559 PNG:

- The wheel is centred around (512, 230).
- The hands are above y = 245.
- The arms run down to the bottom corners.
- The grey background is near RGB (114, 130, 143), or the image can be transparent.

It is **not included**, because permission to redistribute the reference image hasn't been confirmed. If the PC VR mod is installed, the installer finds `VHR-driver.png` in the game folder automatically. Otherwise, pass `-DriverArtwork`.

## Personal use only

The APK the installer builds contains **your copy of the game**. Install it on your own headset; **do not share or upload the APK**.

## How it works

Victory Heat Rally is a GameMaker game, so its bytecode runs on GameMaker's own Android runner.

- `quest/Patch-Quest.csx`, an UndertaleModTool script, patches your `data.win`:
  - It applies the VR camera, cockpit and HUD code from `src/` (shared with the PC VR mod) and the Quest code in `quest/`.
  - It stubs out the Windows-only Steam and ImGui extensions.
- `native/vhrq.c` builds `bin/libvhrvr.so`, the OpenXR bridge. It handles:
  - Headset frames and 120 Hz pacing.
  - Touch input, the virtual wheel and haptics.
  - Foveation and dynamic resolution.
- `java/VHRQuest.java` builds `bin/VHRQuest.dex`, the GameMaker Java extension that forwards to the bridge. It also stops GameMaker's phone-style vsync pacing in VR.
- `quest/build_apk.py` repacks `runner/gamemaker-runner-2024.8.apk` around your patched data:
  - That APK is a blank GameMaker 2024.8 Android export, with no game content.
  - It adds the Quest VR manifest entries and the OpenXR loader.
  - It signs the result with a key created on your PC (`%USERPROFILE%\.vhrquest-key.pem`).
- `quest/tools/gen_driver_art.py` prebakes the recoloured driver art for every car. `quest/paint-table.gml` and `quest/tools/paint-table.json` hold the colours measured from each car.

### Rebuilding the native parts

These steps are optional; prebuilt files are in `bin/`.

- **Bridge:** run `sh native/build.sh` on Linux or WSL. It needs `pip install ziglang` and no Android NDK. It downloads the Khronos OpenXR/EGL/GLES and JNI headers on first run.
- **Java extension:**

  ```sh
  javac --release 8 -d out java/VHRQuest.java
  java -cp <build-tools>/lib/d8.jar com.android.tools.r8.D8 --min-api 29 --output . out/com/segadreamcat/vhrquest/*.class
  ```

  Then rename `classes.dex` to `bin/VHRQuest.dex`.

## Credits and licences

- Mod code: MIT (see `LICENSE`).
- OpenXR loader: © The Khronos Group, Apache-2.0. It is downloaded at install time, not included.
- GameMaker runner: © YoYo Games, included as an exported blank project.
- Victory Heat Rally and its assets belong to their respective owners.

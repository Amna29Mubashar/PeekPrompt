# PeekPrompt

[![Build](https://github.com/Amna29Mubashar/PeekPrompt/actions/workflows/build.yml/badge.svg)](https://github.com/Amna29Mubashar/PeekPrompt/actions/workflows/build.yml)

A teleprompter that lives in your MacBook's notch, right under the camera, so you look straight at your audience while you read.

## Features

- **Sits under the notch.** It tucks into the notch with the same curved "ears", and slides down when shown.
- **Three scrolling modes**
  - **Classic:** scrolls at a steady speed you choose.
  - **Voice-Activated:** scrolls only while you're speaking, and pauses when you go quiet or mute the mic. Turn on **Auto speed** and it matches how fast you talk.
  - **Word Tracking:** listens to the words you say and follows along, even if you skip ahead. Words you've read fade back. Uses Apple's speech recognition, on-device when your Mac supports it.
- **Voice-reactive glowing border.** A rotating gradient outline that brightens and thickens as you talk. Four color palettes.
- **Hidden from screen sharing.** It stays out of Zoom, Meet, Teams, QuickTime and screenshots (see the note on Loom below).
- **Put it anywhere.** Prefer it somewhere else? Switch Position to "Anywhere" and drag it. It becomes a rounded card and remembers where you left it.
- **Right-click menu** for play, restart, position, hide, Settings and Quit.
- **Script library.** Save as many scripts as you like and switch from the right-click menu.
- **Import** .txt, .md, .rtf, Word (.docx) files, or the **speaker notes from a PowerPoint** (.pptx).
- **3-2-1 countdown** before you start.
- **Pacing timer.** Set a target length and see whether you're ahead or behind.
- **Reading-line highlight.** The line you're reading is bright, and the rest is dimmed.
- **Fonts and themes.** Rounded, standard, serif, monospaced or **OpenDyslexic**, in dark or light.
- **Phone remote.** Scan a QR code and control play, speed and more from your phone's browser (same Wi-Fi). No app needed.
- **Hover to pause**, and scroll with your trackpad to jump around.
- **Cues.** Anything in `[square brackets]` is dimmed and italic, so you know not to read it aloud.
- **Global shortcuts** that work from any app.
- **Live mic meter** in Settings, so you can tune voice sensitivity to your room.
- **Private.** The microphone is only measured for loudness. Nothing is recorded, transcribed or sent anywhere.

## Keyboard shortcuts

| Shortcut | Action |
|---|---|
| ⌃⌥P | Play / pause |
| ⌃⌥H | Show / hide |
| ⌃⌥R | Restart from top |
| ⌃⌥M | Mute / unmute mic |
| ⌃⌥↑ / ⌃⌥↓ | Faster / slower |

## A note on Loom and other recorders

PeekPrompt asks macOS to leave its window out of captures (`NSWindow.sharingType = .none`). Zoom, Meet, Teams, QuickTime and the screenshot tool all respect that.

Starting with **macOS 15.4**, recorders built on Apple's ScreenCaptureKit (Loom's full-screen mode is one) can still capture the window. Apple has confirmed there's currently no public API to prevent this, so no notch teleprompter can fully guarantee it.

**Workaround:** in Loom, choose **Camera only** or record a **single window** instead of your full screen. The prompter then never appears in your video.

## Build from source

Requirements: macOS 14 Sonoma or later and Xcode 16 or later.

1. Open `PeekPrompt.xcodeproj` in Xcode.
2. Select the **PeekPrompt** target, open **Signing & Capabilities**, and choose your Team. A free personal Apple ID works.
3. Press **⌘R**. The app appears in the menu bar, and macOS asks for microphone access the first time.

If the project file ever gives you trouble, you can regenerate it with XcodeGen:

```bash
brew install xcodegen
xcodegen generate
```

## Project structure

| File | What it does |
|---|---|
| `PeekPromptApp.swift` | App entry, menu bar menu, global shortcuts setup |
| `PrompterWindowController.swift` | The floating notch window: position, slide animation, capture hiding |
| `PrompterView.swift` | What you see: the script, fades, progress, hover controls |
| `ScrollEngine.swift` | Moves the text 60 times a second, in Classic or Voice mode |
| `MicrophoneMonitor.swift` | Measures voice loudness and detects when you're speaking |
| `GlowBorder.swift` | The voice-reactive animated border |
| `NotchShape.swift` | The notch-style outline |
| `SettingsView.swift` | The Settings window |
| `PrompterSettings.swift` | All settings, saved automatically |
| `GlobalHotKeys.swift` | Shortcuts that work in any app |
| `SpeechTracker.swift` | Word Tracking and Auto speed (speech recognition and matching) |
| `ScriptImporter.swift`, `ZipReader.swift` | Importing documents and PowerPoint notes |
| `RemoteServer.swift` | The phone remote web page and server |
| `Typography.swift` | Fonts and themes |

## Fonts

OpenDyslexic is bundled under the SIL Open Font License (see `PeekPrompt/Fonts/OpenDyslexic-OFL.txt`).

## Credits

Inspired by [NotchPrompter](https://github.com/jpomykala/NotchPrompter) by Jakub Pomykała and [Textream](https://github.com/f/textream) by Fatih Kadir Akın. Both are MIT licensed. PeekPrompt is an independent implementation.

## License

MIT. See [LICENSE](LICENSE).

# App Store listing: PeekPrompt

Copy these into App Store Connect. Character limits were checked.

## App information
- **Name** (30): PeekPrompt: Notch Teleprompter
- **Subtitle** (30): Eye contact while you read
- **Primary category:** Productivity
- **Secondary category:** Business
- **Price:** Free
- **Age rating:** 4+ (no objectionable content)
- **Bundle ID:** com.amnamubashar.PeekPrompt (register it under the UV Apps team)
- **SKU:** PEEKPROMPT-MAC-001
- **Copyright:** © 2026 Amna Mubashar

## URLs
- **Support URL:** https://amna29mubashar.github.io/PeekPrompt/support.html
- **Marketing URL:** https://amna29mubashar.github.io/PeekPrompt/
- **Privacy Policy URL:** https://amna29mubashar.github.io/PeekPrompt/privacy.html

## Promotional text (170)
Read your script right under the camera. PeekPrompt follows your voice, shows one slide at a time, and stays hidden when you share your screen. Free, with no accounts.

## Keywords (100)
teleprompter,prompter,autocue,script,notch,camera,eye contact,presentation,speech,video,zoom,cue

## Description (4000)
PeekPrompt is a teleprompter that lives in your MacBook's notch, right under the camera. Read your script while looking straight at your audience, on video calls, recordings, presentations and interviews.

FOLLOWS YOUR VOICE
• Classic: scrolls at a steady speed you choose.
• Voice-Activated: moves only while you talk and waits when you pause.
• Word Tracking: listens to the words you say and keeps your place, even if you skip a line.
• Auto speed: matches the scrolling to how fast you speak.

BUILT FOR PRESENTING
• Presentation mode shows one slide at a time. Import a PowerPoint and its speaker notes become slides.
• Change slides with keyboard shortcuts, the hover controls, Siri or your phone.
• 3-2-1 countdown and a pacing timer that shows whether you're ahead or behind.

PRACTICE AND WRITE
• Memorize mode hides words step by step so you learn your script.
• Magic Polish turns rough notes into a natural, spoken-style script with Apple Intelligence, right on your Mac.
• Dictate your script, or import text, Markdown, Word, PDF and PowerPoint files.
• Organize scripts in folders and play them back to back.

STAYS OUT OF THE WAY
• Hidden from screen sharing and screenshots in Zoom, Google Meet, Microsoft Teams and QuickTime.
• Hover to pause, scroll with your trackpad, and press ⇧⌘Space to start hands-free.
• Move it anywhere on screen if you'd rather not use the notch.

MAKE IT YOURS
• A glowing border that reacts to your voice, with color choices.
• Rounded, standard, serif, monospaced or OpenDyslexic fonts, in dark or light, with adjustable opacity.
• A phone remote: scan a QR code to control the prompter from your phone's browser on the same Wi-Fi.
• Available in 10 languages.

PRIVATE BY DESIGN
No accounts, no ads, no tracking, and no data collected. Your scripts stay on your Mac.

PeekPrompt is open source. Find the code, guide and support at github.com/Amna29Mubashar/PeekPrompt.

Note: on macOS 15.4 and later, some screen recorders (such as Loom in full-screen mode) can still capture the prompter. Recording a single window or camera only keeps it out of your video.

## App Privacy (in App Store Connect)
Choose **"Data Not Collected"**. The app has no analytics, accounts or tracking, and no data leaves the device through PeekPrompt.

## Notes for App Review
PeekPrompt is a menu bar app (no Dock icon). After launch, a prompter slides down under the notch at the top-center of the screen.

How to test:
• Hover over the prompter to show its controls; click ▶ to start scrolling. Right-click the prompter for a menu with Settings and Quit.
• Settings can also be opened from the menu bar icon (text box symbol) or the ⚙ button in the hover controls.
• Voice-Activated mode and the glowing border use the microphone only to measure loudness. Word Tracking, Auto speed and Dictation use Apple's Speech framework (on-device when supported).
• The phone remote (Settings → Privacy & Keys → Phone remote) is off by default. When turned on, it serves a small control page on the local network only, protected by a random code. It never connects to the internet.
• Magic Polish uses the Foundation Models framework (Apple Intelligence) when available, and a local rule-based cleanup otherwise.
• The prompter window uses NSWindow.sharingType = .none so it is excluded from screen sharing.

No account or sign-in is needed. The app collects no data.

## Export compliance
The app declares `ITSAppUsesNonExemptEncryption = NO`, so no encryption paperwork is needed.

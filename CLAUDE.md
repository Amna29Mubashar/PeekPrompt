# PeekPrompt project rules

## Interface rules (apply to every screen, in both the free and Pro editions)

1. **No text is ever truncated.** No "…" anywhere: labels, settings, buttons, messages, lists.
   - Don't use `.lineLimit(1)` or `.truncationMode`. Let text wrap onto more lines with
     `.fixedSize(horizontal: false, vertical: true)`; short labels that must stay on one line use `.fixedSize()`.
   - Check longer languages (German, French, Arabic) — translations are often 30–50% longer than English.
2. **Every window is resizable** by dragging its edges, like any Mac app.
   - Use `minWidth/idealWidth/maxWidth` (and heights), never a fixed `.frame(width:height:)` on a window's root view.
   - The minimum size must be big enough that nothing is cut off; windows grow when their content needs more room.
3. The prompter itself is the exception to rule 2: its size is set from Appearance settings.

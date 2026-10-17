# UI review checklist

Run on every `#Preview` via Xcode MCP `RenderPreview` (light and dark), then on the bundled running app. Background sessions cannot `screencapture` ("could not create image from display"); use `RenderPreview` or ask the user for a screenshot. Fix every miss before calling UI done.

## Visual

- [ ] Light and dark mode both correct (System Settings > Appearance).
- [ ] Increase Contrast and Reduce Transparency still readable.
- [ ] No hard-coded colors; accent follows system accent.
- [ ] Icons in one column; labels aligned on one leading edge.
- [ ] Spacing from the 4/8/12/16/20 scale, except the menu measurements in `MenuPanel.md` (outer padding 6, 42 pt text column).
- [ ] No text truncation at default size; long SSIDs/names truncate with `…` in the middle or tail, not clipped.
- [ ] Live numbers use `.monospacedDigit()`; nothing jitters while updating.
- [ ] Menu bar icon is a template image and matches system icon weight.

## Behavior

- [ ] Panel opens instantly with last-known data.
- [ ] Loading, empty, error, permission states all reachable and designed.
- [ ] Every action works from the keyboard; Esc backs out then closes.
- [ ] System-changing actions show what changes and confirm once.
- [ ] Network calls to third parties happen only on click and name the service.
- [ ] Panel size does not jump between states.

## Accessibility

- [ ] VoiceOver reads every control with a useful label and value.
- [ ] Icon-only controls have `.help()` tooltips.
- [ ] Reduce Motion replaces slides with fades.

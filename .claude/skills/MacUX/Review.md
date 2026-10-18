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

## Windows and feeds

- [ ] No tile grid of status cards; status is in the toolbar, subtitle or a bottom strip (`Windows.md`).
- [ ] At most 3 toolbar groups, one prominent action, every toolbar command also in the menu bar.
- [ ] No glass on rows, cards or detail; custom glass gated by `#available(macOS 26, *)` with a fallback.
- [ ] Rows: verb-first title, colour only on the leading symbol, each state a distinct symbol shape.
- [ ] Every row has ↵, a context menu and a ⌘K entry; no no-op rows.
- [ ] The window opens **in front** from the panel, the hotkey and the URL scheme, and the Dock icon goes
      away when it closes (checked in the real app, not previews).

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

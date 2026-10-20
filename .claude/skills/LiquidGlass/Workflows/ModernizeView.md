# ModernizeView

1. Read the target view and existing window coordinator. Identify navigation,
   content, controls, settings storage, and the macOS deployment target.
2. Load `../LayersAndMaterials.md` for materials, `../SidebarSettings.md` for
   preferences, or `../GlassChrome.md` for toolbars and typography.
3. Use system containers and preserve existing actions. Use a Settings scene
   separate from the menu panel; choose sidebar navigation for several sections.
4. Apply window materials only where they improve hierarchy and legibility.
   Remove list/form backgrounds only when intentional material should show through.
5. Keep glass in floating navigation or controls, gate macOS 26 APIs, and provide
   a macOS 15 fallback. Preserve native titlebar buttons and window dragging.
6. Compile with the minimum deployment target and render previews in light/dark.
   Test resizing, keyboard navigation, VoiceOver labels, Reduce Transparency,
   Increase Contrast, and activation. Open the app to verify window behavior.
7. Report actual build and visual checks, changes, and any unverified behavior.

A compiler check proves API availability and types. It does not prove material
appearance, accessibility, or focus; do not report those as verified from code alone.

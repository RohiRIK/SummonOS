# Native Chrome and Typography

Use system toolbars, semantic SF Symbols, and readable system type. SF Symbols
are this project's convention for utility actions, not a universal Apple ban on
emoji. Choose symbols available at the minimum deployment target and keep a text
or accessibility label on icon-only controls.

## Toolbar and scope controls

This complete example leaves the toolbar's material under system control. Hide
a toolbar background only when intentional content can safely extend behind it,
and verify the result in active and inactive windows.

```swift
import SwiftUI

struct ActivityScopeView: View {
    enum Scope: String, CaseIterable, Identifiable {
        case all = "All"
        case recent = "Recent"
        var id: Self { self }
    }

    @State private var scope: Scope = .all

    var body: some View {
        Text(scope == .all ? "All activity" : "Recent activity")
            .frame(minWidth: 400, minHeight: 240)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker("Activity filter", selection: $scope) {
                        ForEach(Scope.allCases) { item in
                            Text(item.rawValue).tag(item)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 280)
                }
            }
    }
}
```

## Geometry and labels

- Prefer system capsule and rounded container shapes; inspect custom corner radii
  against enclosing surfaces. Do not assume a named geometry API exists on macOS 15.
- Use `.monospacedDigit()` for changing counters and times to prevent text jitter.
- Preserve readable labels and tooltips; truncation is a deliberate layout choice,
  not a rule for every title or code field.
- Test keyboard traversal, default actions, menu shortcuts, and native traffic lights.

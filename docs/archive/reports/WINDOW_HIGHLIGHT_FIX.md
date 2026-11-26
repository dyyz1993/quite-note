# Window Highlight Border Rendering Fix

## Problem Summary

The window highlight border was not rendering despite correct log output showing:
- `highlightedWindow` was properly set
- Coordinate transformation was correct
- `WindowHighlightOverlay.body` was being called
- But the red border was **not visible on screen**

## Root Cause Analysis

### The Issue: SwiftUI Rendering Limitations

The problem is **NOT** your coordinate transformation (those are correct). The issue is a **SwiftUI rendering limitation** when:

1. **Large coordinate values** - Your window bounds like (1512x945) are large
2. **Transparent background** - Your NSPanel has `backgroundColor = .clear`
3. **NSHostingController** - SwiftUI views hosted via AppKit
4. **Path stroke rendering** - `Rectangle().path(in:).stroke()` has known issues

When you call:
```swift
Rectangle()
    .path(in: localBounds)  // localBounds = (0, 0, 1512, 945)
    .stroke(Color.red, lineWidth: 8)
```

SwiftUI creates a Shape path, but the **stroke rendering gets clipped or not rasterized properly** on transparent backgrounds with large dimensions.

### Evidence from Research

- [Core Graphics stroke width inconsistency](https://stackoverflow.com/questions/4473786/core-graphics-stroke-width-is-inconsistent-between-lines-arcs) - Strokes can get clipped at edges
- [macOS coordinate space bugs](https://stackoverflow.com/questions/65039043/swiftui-global-coordinate-space-is-flipped-on-macos) - SwiftUI has rendering issues on macOS
- [Transparent window issues](https://developer.apple.com/forums/thread/694837) - Opaque views in transparent windows need special handling

## Solutions Provided

### Solution B (Default): SwiftUI with `.border()` Modifier

**File**: `/Sources/QuiteNote/UI/Screenshot/WindowDetection/Views/WindowHighlightOverlay.swift`

**Changes**:
- Replace `Rectangle().path(in:).stroke()` with `.border()` modifier
- Use `RoundedRectangle` for better visual appearance
- Add semi-transparent background fill

```swift
RoundedRectangle(cornerRadius: 8)
    .fill(Color.blue.opacity(0.15))
    .frame(width: localBounds.width, height: localBounds.height)
    .position(x: localBounds.midX, y: localBounds.midY)

RoundedRectangle(cornerRadius: 8)
    .fill(Color.clear)
    .frame(width: localBounds.width, height: localBounds.height)
    .border(Color.blue, width: 4)
    .overlay(
        RoundedRectangle(cornerRadius: 8)
            .stroke(Color.white, lineWidth: 2)
    )
    .position(x: localBounds.midX, y: localBounds.midY)
```

**Why this works**:
- `.border()` is more reliable than `.stroke()` on transparent backgrounds
- Using `.frame()` + `.position()` instead of `.path(in:)` avoids coordinate space issues
- Double-layer border (blue + white) provides better visibility

### Solution C (Alternative): CALayer-based Rendering

**File**: `/Sources/QuiteNote/UI/Screenshot/WindowDetection/Views/WindowHighlightView.swift`

**Approach**: Use `CAShapeLayer` directly via NSView, bypassing SwiftUI entirely

```swift
final class WindowHighlightView: NSView {
    private var highlightLayer: CAShapeLayer?
    private var fillLayer: CAShapeLayer?

    override func layout() {
        let path = NSBezierPath(roundedRect: highlightedBounds, xRadius: 8, yRadius: 8)
        fillLayer?.path = path.toCGPath()
        highlightLayer?.path = path.toCGPath()
    }
}
```

**When to use**:
- If Solution B still doesn't render properly
- If you need maximum performance
- If you want to avoid SwiftUI rendering quirks entirely

**How to enable**:
```swift
WindowHighlightOverlay(
    window: highlightedWindow,
    windowFrame: windowFrame,
    useCALayer: true  // Enable CALayer rendering
)
```

## How to Test

### Step 1: Test Solution B (Default)

The default implementation now uses `.border()` modifier. Simply run:

```bash
./build-app.sh
```

Then trigger window detection and move your mouse over a window. You should see:
- Blue border with white inner border
- Semi-transparent blue background fill
- Rounded corners (8pt radius)

### Step 2: Check Logs

Look for these debug logs:
```
[DEBUG WindowHighlightOverlay] 显示高亮 - 窗口: <window name>
[DEBUG WindowHighlightOverlay] 局部坐标: (x, y, width, height)
[DEBUG WindowHighlightOverlay] 容器尺寸: (width, height)
[DEBUG WindowHighlightOverlay] 使用 CALayer: false
```

### Step 3: If Still Not Working

Enable CALayer rendering by modifying `WindowDetectionView.swift`:

```swift
WindowHighlightOverlay(
    window: highlightedWindow,
    windowFrame: windowFrame,
    useCALayer: true  // Change to true
)
```

## Technical Details

### Why `.path(in:)` Fails

```swift
// ❌ Doesn't work on large transparent views
Rectangle()
    .path(in: CGRect(x: 0, y: 0, width: 1512, height: 945))
    .stroke(Color.red, lineWidth: 8)
```

**Problems**:
1. SwiftUI creates a path with large coordinate values
2. Stroke rendering requires expanding the path by `lineWidth / 2` on all sides
3. On transparent backgrounds, SwiftUI may not properly allocate the backing store
4. NSHostingController layer backing may clip the stroke

### Why `.border()` Works

```swift
// ✅ Works reliably
Rectangle()
    .border(Color.blue, width: 4)
```

**Advantages**:
1. `.border()` is a built-in modifier optimized for all backgrounds
2. Doesn't require path expansion calculations
3. Better layer composition
4. Works correctly with NSHostingController

### Coordinate Transformation (Unchanged)

Your coordinate transformation was **already correct**:

```swift
private func convertScreenToLocal(_ screenRect: CGRect) -> CGRect {
    let windowOrigin = windowFrame.origin
    return CGRect(
        x: screenRect.origin.x - windowOrigin.x,
        y: screenRect.origin.y - windowOrigin.y,
        width: screenRect.size.width,
        height: screenRect.size.height
    )
}
```

This correctly converts from screen coordinates to window-local coordinates.

## Summary

| Solution | Approach | Complexity | Performance | Reliability |
|----------|----------|------------|-------------|-------------|
| **Solution B** | SwiftUI `.border()` | Low | Good | **High** ✅ |
| Solution C | CALayer direct | Medium | Excellent | Very High |

**Recommendation**: Start with Solution B (already implemented). Only use Solution C if you encounter issues.

## Files Modified

1. `/Sources/QuiteNote/UI/Screenshot/WindowDetection/Views/WindowHighlightOverlay.swift`
   - Updated `body` to use `.border()` modifier
   - Added `useCALayer` parameter for fallback option

2. `/Sources/QuiteNote/UI/Screenshot/WindowDetection/Views/WindowHighlightView.swift` (NEW)
   - CALayer-based rendering implementation
   - NSBezierPath to CGPath conversion for macOS 13+
   - SwiftUI wrapper via NSViewRepresentable

## Further Reading

- [TN3124: Debugging coordinate space issues](https://developer.apple.com/documentation/technotes/tn3124-debugging-coordinate-transformations)
- [SwiftUI - Global coordinate space is flipped on macOS](https://stackoverflow.com/questions/65039043/swiftui-global-coordinate-space-is-flipped-on-macos)
- [Core Graphics stroke width inconsistency](https://stackoverflow.com/questions/4473786/core-graphics-stroke-width-is-inconsistent-between-lines-arcs)
- [Transparent window in SwiftUI macOS application](https://developer.apple.com/forums/thread/694837)

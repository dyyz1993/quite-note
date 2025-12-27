# Screenshot Coordinate System Documentation

## Overview

This document describes the coordinate systems used in the screenshot preview feature and how to properly transform between them. Understanding these coordinate systems is critical for implementing tools like the magnifier, crop box, and other interactive elements.

---

## Coordinate Systems

### 1. Screen/Window Coordinates (屏幕/窗口坐标)
- **Origin**: Top-left corner of the window
- **Range**: (0, 0) to (windowWidth, windowHeight)
- **Used by**: NSEvent, window-level operations
- **Example**: `NSEvent.mouseLocation` (screen global)

### 2. ZStack Global Coordinates (ZStack 全局坐标)
- **Origin**: Top-left corner of the ZStack containing the screenshot preview
- **Range**: (0, 0) to (zStackWidth, zStackHeight)
- **Used by**: `onContinuousHover`, some GeometryReader operations
- **Offset to Canvas**: (80, 130) - This is the offset from ZStack origin to Canvas origin
- **Important**: This coordinate system includes the toolbar and other UI elements

### 3. Canvas Local Coordinates (Canvas 本地坐标)
- **Origin**: Top-left corner of the Canvas view itself
- **Range**: (0, 0) to (canvasWidth, canvasHeight)
- **Used by**: `DragGesture`, Canvas drawing operations
- **Offset to ZStack**: (0, 0) relative to Canvas, (80, 130) relative to ZStack
- **Important**: This is the coordinate system used for all drawing operations

---

## Coordinate Transformation

### ZStack → Canvas Conversion

```swift
/// 将全局坐标（ZStack）转换为 Canvas 内部坐标
private func convertToCanvasCoordinates(_ point: CGPoint) -> CGPoint {
    let offsetX: CGFloat = 80
    let offsetY: CGFloat = 130  // 30 (toolbar) + 60 (toolbar height) + 40 (padding) = 130

    let result = CGPoint(
        x: point.x - offsetX,
        y: point.y - offsetY
    )

    print("[DEBUG COORD] ZStack(\(point.x), \(point.y)) -> Canvas(\(result.x), \(result.y))")
    return result
}
```

### Canvas → ZStack Conversion

```swift
/// 将 Canvas 内部坐标转换为 ZStack 全局坐标
private func convertToZStackCoordinates(_ point: CGPoint) -> CGPoint {
    let offsetX: CGFloat = 80
    let offsetY: CGFloat = 130

    let result = CGPoint(
        x: point.x + offsetX,
        y: point.y + offsetY
    )

    print("[DEBUG COORD] Canvas(\(point.x), \(point.y)) -> ZStack(\(result.x), \(result.y))")
    return result
}
```

---

## Critical Rule: When to Convert

### ✅ Requires Conversion: onContinuousHover

```swift
// CORRECT: onContinuousHover provides ZStack coordinates, NEEDS conversion
.onContinuousHover { phase in
    if case .changed(let mouseLocation) = phase {
        let canvasMouseLocation = convertToCanvasCoordinates(mouseLocation)
        // Use canvasMouseLocation for preview calculations
    }
}
```

### ❌ NO Conversion Needed: DragGesture

```swift
// CORRECT: DragGesture provides Canvas local coordinates, NO conversion
.gesture(
    DragGesture(coordinateSpace: .named(canvasSpace))
        .onChanged { value in
            let canvasLocation = value.location  // Already in Canvas space
            // Use canvasLocation directly
        }
)

// WRONG: Don't convert DragGesture coordinates
let canvasLocation = convertToCanvasCoordinates(value.location)  // ❌ INCORRECT
```

---

## Common Pitfalls

### Pitfall 1: Converting DragGesture Coordinates

**Problem**: Applying coordinate conversion to DragGesture coordinates

```swift
// ❌ WRONG
private func handleDragChanged(_ value: DragGesture.Value, in size: CGSize) {
    let canvasStartLocation = convertToCanvasCoordinates(value.startLocation)
    let canvasCurrentLocation = convertToCanvasCoordinates(value.location)
    // ...
}

// ✅ CORRECT
private func handleDragChanged(_ value: DragGesture.Value, in size: CGSize) {
    let canvasStartLocation = value.startLocation  // Already Canvas coordinates
    let canvasCurrentLocation = value.location     // Already Canvas coordinates
    // ...
}
```

**Symptoms**:
- Elements "float upward" after clicking
- Coordinates don't align with cursor
- Elements appear in wrong positions

### Pitfall 2: Not Converting Hover Coordinates

**Problem**: Not applying coordinate conversion to hover coordinates

```swift
// ❌ WRONG
.onContinuousHover { phase in
    if case .changed(let mouseLocation) = phase {
        // Using mouseLocation directly without conversion
        updatePreview(at: mouseLocation)  // Wrong coordinate system
    }
}

// ✅ CORRECT
.onContinuousHover { phase in
    if case .changed(let mouseLocation) = phase {
        let canvasLocation = convertToCanvasCoordinates(mouseLocation)
        updatePreview(at: canvasLocation)
    }
}
```

**Symptoms**:
- Preview doesn't follow cursor correctly
- Offset between cursor and preview element
- Inconsistent behavior across different screen positions

### Pitfall 3: Mixing Coordinate Systems

**Problem**: Storing coordinates from different systems without normalization

```swift
// ❌ WRONG: Mixing coordinate systems
struct DrawingElement {
    var points: [CGPoint]  // Could be ZStack or Canvas coordinates
}

// ✅ CORRECT: Always normalize to Canvas coordinates
struct DrawingElement {
    var points: [CGPoint]  // Always Canvas coordinates
}

// When adding points from different sources:
// From DragGesture: Direct use
element.points.append(dragLocation)

// From onContinuousHover: Convert first
element.points.append(convertToCanvasCoordinates(hoverLocation))
```

---

## Debugging Techniques

### 1. Visual Debugging with Colored Dots

```swift
// Draw a red dot at the click location
context.fill(Path(ellipseIn: CGRect(x: clickLocation.x-5, y: clickLocation.y-5, width: 10, height: 10)),
            with: .color(.red))

// Draw a green dot at the expected location
context.fill(Path(ellipseIn: CGRect(x: expectedLocation.x-5, y: expectedLocation.y-5, width: 10, height: 10)),
            with: .color(.green))
```

### 2. Console Logging

```swift
private func convertToCanvasCoordinates(_ point: CGPoint) -> CGPoint {
    let result = CGPoint(
        x: point.x - offsetX,
        y: point.y - offsetY
    )

    // Log all coordinate transformations
    print("[DEBUG COORD] ZStack(\(point.x), \(point.y)) -> Canvas(\(result.x), \(result.y))")
    return result
}
```

### 3. Real-time Log Monitoring

```bash
# Monitor logs in real-time
log stream --predicate 'process == "QuiteNote"' --level debug
```

---

## Best Practices

### 1. Single Source of Truth

**Always store coordinates in a single coordinate system** (Canvas local coordinates recommended).

```swift
// Good: Always normalize to Canvas coordinates
private func addPoint(_ point: CGPoint, from source: CoordinateSource) {
    let canvasPoint: CGPoint
    switch source {
    case .dragGesture:
        canvasPoint = point  // No conversion needed
    case .hover:
        canvasPoint = convertToCanvasCoordinates(point)  // Convert
    }
    element.points.append(canvasPoint)
}
```

### 2. Coordinate Source Tracking

```swift
enum CoordinateSource {
    case dragGesture      // Canvas coordinates, no conversion
    case hover            // ZStack coordinates, needs conversion
    case canvas           // Canvas coordinates, no conversion
}
```

### 3. Dynamic Position Calculation

For elements with calculated positions (like magnifier in corner), calculate at render time rather than storing:

```swift
// ❌ WRONG: Store both source and display position
struct DrawingElement {
    var sourcePoint: CGPoint      // Where user clicked
    var displayPosition: CGPoint   // Where magnifier appears (wastes space)
}

// ✅ CORRECT: Store only source, calculate display at render time
struct DrawingElement {
    var sourcePoint: CGPoint       // Where user clicked
    // Display position calculated dynamically in renderer
}

// In renderer:
func render(element: DrawingElement, ...) {
    let source = element.sourcePoint
    let displayPosition = calculateMagnifierPosition(in: config.canvasSize)
    // ...
}
```

### 4. Named Coordinate Spaces

Use SwiftUI's named coordinate spaces for reliable transformations:

```swift
Canvas { ... }
    .coordinateSpace(name: "CanvasSpace")

ZStack {
    // ...
}
    .coordinateSpace(name: "ZStackSpace")
```

---

## Tool-Specific Guidelines

### Magnifier Tool

1. **Preview Phase**: Use `onContinuousHover` + `convertToCanvasCoordinates`
2. **Click Phase**: Use `DragGesture.startLocation` directly (no conversion)
3. **Render Phase**: Calculate display position dynamically from Canvas size

```swift
// Preview: Convert hover coordinates
.onContinuousHover { phase in
    if case .changed(let mouseLocation) = phase {
        let canvasLocation = convertToCanvasCoordinates(mouseLocation)
        previewMagnifierPosition = canvasLocation
    }
}

// Click: Use DragGesture coordinates directly
.gesture(
    DragGesture(coordinateSpace: .named(canvasSpace))
        .onEnded { value in
            let canvasClickLocation = value.startLocation  // Direct use
            createMagnifier(at: canvasClickLocation)
        }
)
```

### Crop Box Tool

1. **Drag Operations**: Use `DragGesture` coordinates directly
2. **Handle Detection**: Compare with Canvas-space coordinates
3. **Size Limits**: Apply to Canvas-space dimensions

```swift
private func handleDragChanged(_ value: DragGesture.Value, in size: CGSize) {
    if selectedTool == .cursor {
        let delta = CGSize(
            width: value.location.x - value.startLocation.x,
            height: value.location.y - value.startLocation.y
        )
        cropRect.origin.x += delta.width
        cropRect.origin.y += delta.height
    }
}
```

---

## Summary

| Coordinate System | Source | Conversion Needed | Offset |
|------------------|--------|-------------------|--------|
| Screen/Window | NSEvent | Yes (to window) | Varies |
| ZStack Global | onContinuousHover | **YES** (to Canvas) | (80, 130) |
| Canvas Local | DragGesture, Canvas | **NO** | (0, 0) |

**Key Takeaway**: Only convert coordinates from `onContinuousHover`. All DragGesture coordinates are already in Canvas space.

---

## Related Files

- `ScreenshotPreviewView.swift` - Main screenshot preview interface
- `MagnifierRenderer.swift` - Magnifier rendering logic
- `DrawingElement.swift` - Drawing element data model
- `AnnotationTool.swift` - Tool definitions

---

## Version History

- **2025-12-26**: Initial documentation created after fixing magnifier coordinate alignment issue
  - Documented ZStack vs Canvas coordinate systems
  - Added conversion rules and common pitfalls
  - Included debugging techniques and best practices

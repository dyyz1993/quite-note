# Three-Phase Screenshot Feature Architecture

## Overview

This document describes the architecture of the three-phase screenshot feature in QuiteNote. The feature currently uses a two-phase approach (`isCropping` boolean), but the design analysis reveals the benefits of a proper three-phase state machine.

---

## Phase Definitions

### Phase 1: Area Selection (Cropping Phase)
**Purpose**: User selects the area to capture from the full screenshot.

**Characteristics**:
- Show full screenshot with semi-transparent overlay
- Display adjustable crop box with 8 handles
- Bottom action bar: "Full Screen", "Confirm", "Cancel"
- Tools disabled in toolbar
- Cursor: Resize cursors (diagonal, edge, move)

**Current State**: `isCropping = true`

### Phase 2: Annotation (Editing Phase)
**Purpose**: User adds annotations to the selected area.

**Characteristics**:
- Show cropped area only
- Full toolbar enabled with all annotation tools
- Canvas-based rendering for all elements
- Text editing layer overlays
- Cursor: Tool-specific cursors (arrow, crosshair, pointing hand)

**Current State**: `isCropping = false`

### Phase 3: Export/Save (Completion Phase)
**Purpose**: User saves or exports the annotated screenshot.

**Characteristics**:
- Triggers callbacks: `onSave()`, `onCancel()`
- Window closes
- Image saved to clipboard or file

**Current State**: Not explicitly modeled, handled via callbacks

---

## Current State Management

### Existing: Boolean State (Current Implementation)

```swift
// Current approach in ScreenshotPreviewView.swift
@State private var isCropping = true
```

**Limitations**:
1. Only two states, no explicit completion state
2. State transitions scattered across multiple callback locations
3. Hard to track which phase is active
4. No way to represent intermediate states

### Proposed: Enum State (Future Enhancement)

```swift
enum ScreenshotPhase {
    case cropping        // Phase 1: Area selection
    case annotating      // Phase 2: Adding annotations
    case completed       // Phase 3: Done (for cleanup)
}
```

**Advantages**:
1. Explicit state representation
2. Compile-time safety for state transitions
3. Easier to add new states (e.g., `previewing`)
4. Better debugging with state logging
5. Clear separation of concerns

---

## State Machine Diagram

```
                    User cancels
    +-------------------<-------------------+
    |                                       |
    v                                       |
+-----------+   User confirms   +-----------+
|  Cropping | ---------------> | Annotating |
|   Phase   |                  |   Phase    |
+-----------+                  +-----------+
    |                               |
    | User selects "Full Screen"    |
    |                               | User saves
    |                               v
    |                          +-----------+
    |                          | Completed |
    +-----------------------> |   Phase   |
           User cancels       +-----------+
```

### State Transition Triggers

| From State | To State | Trigger | Handler |
|------------|----------|---------|---------|
| Cropping | Annotating | User clicks "Confirm" or "Full Screen" | `isCropping = false` |
| Cropping | Completed | User clicks "Cancel" | `onCancel()` |
| Annotating | Completed | User saves or exits | `onSave()` or `onCancel()` |
| Annotating | (self) | User switches tool | `selectedTool = ...` |

---

## View Hierarchy Architecture

### Tree Structure

```
ZStack (coordinateSpace: "zstackSpace")
│
├── Color.clear (background tap handler, Phase 2 only)
│   └── .onTapGesture (deselect elements)
│
└── VStack (spacing: 0)
    │
    ├── ScreenshotToolbar (always visible)
    │   ├── Tool selection groups (select, shape, line, text, draw, effect)
    │   ├── Size/Font selector (conditional: text, mosaic, magnifier)
    │   ├── Color picker (always visible)
    │   └── Action buttons (undo, cancel, copy, save)
    │
    └── ZStack (Canvas area)
        │
        ├── Phase 1: Cropping Mode
        │   └── GeometryReader
        │       └── ZStack (alignment: .topLeading)
        │           ├── Image (full screenshot)
        │           └── cropOverlayLayer
        │               ├── Semi-transparent background
        │               ├── Crop border (dashed)
        │               ├── 8 resize handles
        │               ├── Size indicator
        │               └── DragGesture (crop adjustment)
        │
        ├── Phase 2: Editing Mode
        │   ├── Canvas (unified rendering)
        │   │   └── Canvas { context, size in
        │   │       ├── Base image layer
        │   │       ├── Spotlight background (if any)
        │   │       ├── Drawing elements (for loop)
        │   │       ├── Current element (being drawn)
        │   │       ├── Magnifier preview (tool selected)
        │   │       └── Selection indicators
        │   │   }
        │   │   ├── DragGesture (drawing/selecting)
        │   │   └── .preference(key: CanvasFramePreferenceKey)
        │   │
        │   └── textEditLayer (overlay)
        │       └── ForEach(elements) { TextEditor(...) }
        │
        └── Bottom Action Bar (Phase 1 only)
            ├── Button("Full Screen")
            ├── Button("Confirm")
            └── Button("Cancel")
```

### Conditional Rendering Logic

```swift
// Phase 1: Cropping
if isCropping {
    // Show: full screenshot + crop overlay
    // Hide: Canvas, textEditLayer
    // Enable: crop handles, bottom action bar
    // Disable: toolbar tools (visually dimmed)
}

// Phase 2: Annotation
else {
    // Show: Canvas (cropped area), textEditLayer
    // Hide: crop overlay, bottom action bar
    // Enable: all toolbar tools
}
```

---

## Cursor Management Architecture

### Cursor State Machine

```
                    Phase 1: Cropping
                          |
                          v
        +---------------------------------+
        |                                 |
    v   v   v   v   v   v   v   v   v   v
[ 8 Resize Cursors + Move Cursor ]
        |                                 |
        +---------------------------------+
                          |
                    User confirms
                          |
                          v
                    Phase 2: Annotation
                          |
          +---------------+---------------+
          |               |               |
          v               v               v
    [Tool-specific cursors per tool]
          |               |               |
  +-------+-------+       |       +-------+-------+
  |               |       |       |               |
  v               v       v       v               v
[Arrow]      [Crosshair]  [PointingHand]   [CustomMagnifier]
(default)    (drawing)   (selectable)     (magnifier tool)
```

### Cursor Hierarchy by Phase

**Phase 1 (Cropping)** - Priority: Handles > Center > Outside:
- Corner handles (TL, TR, BL, BR): Diagonal resize cursors
- Edge handles (T, B, L, R): Edge resize cursors
- Center: Move cursor
- Outside: Arrow cursor

**Phase 2 (Annotation)** - Priority: Tool > Hover > Default:
- Magnifier tool: Custom crosshair cursor
- Cursor tool + hovering element: Pointing hand
- Cursor tool + not hovering: Arrow cursor
- Other tools: Arrow cursor (or tool-specific)

### Cursor Update Flow

```
.onContinuousHover { phase in
    if case .active(let location) = phase {
        mouseLocation = location
        updateCursor(at: location)  // <-- Centralized cursor logic
    }
}

private func updateCursor(at location: CGPoint) {
    // 1. Check phase
    guard !isCropping else {
        // Phase 1: Handle-based cursor
        let handle = getHandle(at: location)
        setCursorForHandle(handle)
        return
    }

    // 2. Check tool-specific cursor
    if selectedTool == .magnifier {
        magnifierCursor?.set()
        return
    }

    // 3. Check hover state
    let canvasLocation = convertToCanvasCoordinates(location)
    if hitTest(canvasLocation) != nil {
        NSCursor.pointingHand.set()
        return
    }

    // 4. Default
    NSCursor.arrow.set()
}
```

---

## Event Handling Architecture

### Event Flow Diagram

```
User Input Events
        |
        v
+-------------------+
| NSEvent Monitor   | (keyDown: ESC, Enter, Cmd+C, Cmd+S, Delete)
+-------------------+
        |
        +--> handleEscape()
        |    |
        |    +--> if editingTextId != nil: finish editing
        |    +--> elif selectedElementId: deselect
        |    +--> elif showExitConfirm: cancel
        |    +--> else: show exit confirmation
        |
        +--> handleEnter()
        |    |
        |    +--> if editingTextId: finish editing + select
        |    +--> else: switch to cursor tool
        |
        +--> Cmd+S / Cmd+C / Delete: actions
        |
        v
Mouse/Touch Events
        |
        v
+-------------------+
| DragGesture       | (Canvas coordinate space)
+-------------------+
        |
        +--> .onChanged { value in
        |    |
        |    +--> if selectedTool == .cursor:
        |    |    +--> select element / move element
        |    |
        |    +--> elif currentElement == nil:
        |    |    +--> create new element
        |    |
        |    +--> else:
        |         +--> append points to currentElement
        |    }
        |
        +--> .onEnded {
             +--> finalize element
             +--> stepCounter++ (for steps tool)
        }
```

### Key Event Handlers

| Event | Handler | Phase | Action |
|-------|---------|-------|--------|
| ESC | `handleEscape()` | Both | Multi-level cancel: editing -> selection -> exit confirm -> cancel |
| Enter | `handleEnter()` | Both | Finish text editing / switch to cursor |
| Cmd+S | `onSave()` | Both | Save and exit |
| Cmd+C | `copyToClipboard()` | Both | Copy to clipboard |
| Delete/Backspace | `deleteSelectedElement()` | 2 only | Delete selected element |
| Mouse Drag | `handleDragChanged()` | 2 only | Create/move elements |
| Handle Drag | `handleCropDrag()` | 1 only | Resize/move crop box |

### Event Bubbling and Capture

```
ZStack (root)
  │
  ├── .onContinuousHover (captures hover, converts coordinates)
  │
  ├── Color.clear.onTapGesture (background tap, deselects)
  │
  └── VStack
        │
        └── ZStack (Canvas area)
              │
              ├── cropOverlayLayer.gesture(DragGesture)  [Phase 1]
              │
              └── Canvas.gesture(DragGesture)             [Phase 2]
```

---

## Data Flow Architecture

### State to Rendering Pipeline

```
State Changes (@State variables)
        |
        v
+-------------------+
| View Re-computation |
+-------------------+
        |
        v
+-------------------+
| Conditional Rendering |
| (isCropping)         |
+-------------------+
        |
        +--> true:  cropOverlayLayer
        |
        +--> false: Canvas + textEditLayer
                    |
                    v
            +-------------------+
            | Canvas Renderer   |
            +-------------------+
                    |
                    +--> For each element:
                    |    |
                    |    +--> Get renderer from ElementRendererFactory
                    |    +--> Call render(element, in: &context, config:)
                    |    +--> Renderer draws to context
                    |
                    +--> Selection indicators
                    +--> Magnifier preview (if tool selected)
```

### Data Transformation Flow

```
User Action (e.g., draw rectangle)
        |
        v
DragGesture.onChanged { value in
        |
        +--> value.location (Canvas coordinates)
        |
        v
currentElement.points.append(location)
        |
        v
@State var currentElement: DrawingElement? triggers redraw
        |
        v
Canvas { context, size in
        |
        +--> drawElement(currentElement, ...)
        |
        v
ShapeRenderer.render(...)
        |
        v
context.stroke(Path(rectangle), ...)
        |
        v
Display update (60 FPS)
}
```

### Coordinate System Integration

```
ZStack Global Coordinates
        |
        | convertToCanvasCoordinates()
        v
Canvas Local Coordinates (normalized storage)
        |
        | ElementRenderer.render()
        v
GraphicsContext Drawing (relative to Canvas origin)
```

---

## Key Decision Points

### Decision Point 1: Phase Transition

**Location**: `ScreenshotToolbar.onToolSelect`, `setupInitialCrop`, bottom action buttons

**Logic**:
```swift
// When should we transition from Cropping to Annotation?
if isCropping && (userClickedTool || userClickedConfirm) {
    isCropping = false
    // Effect: Switch from cropOverlayLayer to Canvas
}
```

**Rationale**: The transition should happen when:
1. User explicitly confirms crop area
2. User selects a tool (implicit confirmation)
3. User selects "Full Screen" (bypass cropping)

### Decision Point 2: Cursor Selection

**Location**: `updateCursor(at:)`

**Logic**:
```swift
// Priority hierarchy:
if isCropping {
    // Phase 1: Handle-based cursor
    setCursorForCropHandle(location)
} else if selectedTool == .magnifier {
    // Phase 2: Tool-specific cursor
    setCustomMagnifierCursor()
} else if hitTest(canvasLocation) != nil {
    // Phase 2: Hover state cursor
    NSCursor.pointingHand.set()
} else {
    // Default
    NSCursor.arrow.set()
}
```

**Rationale**: Cursor must provide immediate visual feedback for:
- Current phase (cropping vs editing)
- Active tool (magnifier needs crosshair)
- Interactive state (hovering over selectable elements)

### Decision Point 3: Coordinate Conversion

**Location**: `convertToCanvasCoordinates()`, called from `updateCursor`, magnifier preview

**Logic**:
```swift
// When to convert?
if source == .onContinuousHover {
    return convertToCanvasCoordinates(point)  // YES
} else if source == .dragGesture {
    return point  // NO (already Canvas coordinates)
}
```

**Rationale**: Different event sources provide coordinates in different systems:
- `onContinuousHover`: ZStack global coordinates (needs conversion)
- `DragGesture`: Canvas local coordinates (no conversion)
- NSEvent: Screen coordinates (needs window + ZStack + Canvas conversion)

### Decision Point 4: Element Hit Testing

**Location**: `hitTest(_:at:)`, called from cursor update and drag handling

**Logic**:
```swift
// Reverse iteration (topmost first)
for element in elements.reversed() {
    if hitTest(element, at: point) {
        return element  // First match wins
    }
}
```

**Rationale**: Hit testing must account for:
- Tool-specific hit regions (magnifier has 3 distinct areas)
- Visual bounding boxes vs logical hit areas
- Z-order (reverse iteration for topmost)
- Padding for better UX (insetBy negative values)

### Decision Point 5: Text Editing Mode

**Location**: `handleDragChanged`, `handleEscape`, `handleEnter`

**Logic**:
```swift
// When to enter text editing mode?
if selectedTool == .text && currentElement == nil {
    // Create element immediately on click
    elements.append(newElement)
    editingTextId = newElement.id
    // Show TextEditor overlay
}
```

**Rationale**: Text editing is special because:
- Requires TextField overlay (not Canvas drawing)
- Blocks other interactions while editing
- Needs multi-step exit (Enter confirms, ESC cancels editing)
- Syncs with toolbar fontSize/color

---

## Relationship to Coordinate System

The three-phase architecture builds upon the coordinate system documented in `COORDINATE_SYSTEM.md`:

### Coordinate Usage by Phase

**Phase 1 (Cropping)**:
- Uses: ZStack global coordinates
- Offset: (80, 40) - padding to crop overlay
- No Canvas involved

**Phase 2 (Annotation)**:
- Uses: Canvas local coordinates for all elements
- Conversion: Required for hover events
- Storage: All points in Canvas coordinates

### Shared Components

1. **Coordinate Conversion Functions**:
   - `convertToCanvasCoordinates()` - Used in both phases for cursor
   - `convertFromCanvasCoordinates()` - Used for hit testing bounds

2. **Named Coordinate Spaces**:
   - `"zstackSpace"` - Root coordinate space for hover events
   - `.named(canvasSpace)` - DragGesture coordinate space

3. **PreferenceKey Communication**:
   - `CanvasFramePreferenceKey` - Passes Canvas frame to parent
   - Enables dynamic coordinate conversion

---

## Renderer Architecture

### Renderer Factory Pattern

```
ElementRendererFactory.renderer(for: tool)
        |
        v
+-------------------+---------------+-------+-------+
|                   |               |       |       |
v                   v               v       v       v
ShapeRenderer    ArrowRenderer   PenRenderer  TextRenderer  Others
(rectangle,    (arrow)         (freehand)   (text)
circle, line)
```

### Renderer Configuration

```swift
struct RendererConfig {
    let imageSize: CGSize      // Original screenshot size
    let canvasSize: CGSize     // Current Canvas render size
    let baseImage: NSImage?    // Source image for magnifier
}
```

**Purpose**: Provides renderers with context needed for:
- Scaling calculations (magnifier)
- Image cropping (mosaic, spotlight)
- Size-based rendering (text steps)

---

## Memory and Performance

### Memory Optimization

1. **Pagination (Not implemented yet)**:
   - Current: All elements in memory
   - Proposed: Limit to 200 elements, lazy load older

2. **Canvas Caching**:
   - Each redraw re-renders all elements
   - Consider caching static background

3. **Coordinate Caching**:
   - `canvasFrameInZStack` cached via PreferenceKey
   - `actualCanvasSize` cached on first render

### Performance Considerations

1. **Hit Testing**:
   - O(n) where n = number of elements
   - Optimized by reverse iteration (topmost first)

2. **Rendering**:
   - O(n) per frame (60 FPS)
   - Each renderer handles its own complexity

3. **Drag Gesture**:
   - Throttled by SwiftUI
   - Consider debouncing for pen tool

---

## Extension Points

### Adding a New Phase

```swift
enum ScreenshotPhase {
    case cropping
    case annotating
    case previewing      // NEW: Show final result
    case completed
}
```

### Adding a New Tool

1. Add to `AnnotationTool` enum
2. Create renderer implementing `ElementRenderer`
3. Add to `ElementRendererFactory.renderer(for:)`
4. Add icon to toolbar group
5. Implement hit testing if needed

### Adding a New Cursor

```swift
private func createCustomCursor() -> NSCursor {
    let image = NSImage(size: NSSize(width: 24, height: 24))
    image.lockFocus()
    // Draw cursor...
    image.unlockFocus()
    return NSCursor(image: image, hotSpot: NSPoint(x: 12, y: 12))
}
```

---

## Troubleshooting

### Common Issues

1. **Elements "float upward" after clicking**:
   - Cause: Double coordinate conversion
   - Fix: Don't convert DragGesture coordinates

2. **Cursor doesn't update**:
   - Cause: `updateCursor` not called
   - Fix: Add `.onContinuousHover` to ZStack

3. **Text editor appears in wrong position**:
   - Cause: Using Canvas coordinates directly
   - Fix: Convert to ZStack coordinates

4. **Magnifier preview doesn't follow cursor**:
   - Cause: Not converting hover coordinates
   - Fix: Use `convertToCanvasCoordinates(location)`

### Debug Logging

```swift
// Enable coordinate logging
print("[DEBUG COORD] ZStack(\(x), \(y)) -> Canvas(\(newX), \(newY))")

// Enable state logging
print("[DEBUG STATE] Phase: \(isCropping ? "cropping" : "annotating"), Tool: \(selectedTool)")

// Enable cursor logging
print("[DEBUG CURSOR] Handle: \(handle), Tool: \(selectedTool)")
```

---

## Migration Path to Enum State

### Step 1: Add Enum

```swift
enum ScreenshotPhase {
    case cropping
    case annotating
    case completed
}

@State private var phase: ScreenshotPhase = .cropping
```

### Step 2: Replace Boolean

```swift
// Before
if isCropping { ... }

// After
if phase == .cropping { ... }
```

### Step 3: Add Transitions

```swift
func transitionToPhase(_ newPhase: ScreenshotPhase) {
    print("[DEBUG PHASE] \(phase) -> \(newPhase)")
    phase = newPhase
}
```

### Step 4: Update UI

```swift
var body: some View {
    switch phase {
    case .cropping:
        cropOverlayLayer
    case .annotating:
        canvasView
    case .completed:
        EmptyView()  // Window will close
    }
}
```

---

## Summary

| Aspect | Current (Boolean) | Proposed (Enum) |
|--------|-------------------|-----------------|
| States | 2 (cropping, editing) | 3+ (cropping, annotating, completed, previewing) |
| Type Safety | Bool (limited) | Enum (exhaustive) |
| Transitions | Implicit (callbacks) | Explicit (functions) |
| Debugging | Print statements | State logging + transitions |
| Extensibility | Hard (add new bool) | Easy (add enum case) |

The three-phase architecture provides a clear separation of concerns and enables future enhancements like preview mode, multi-step workflows, and undo/redo across phase boundaries.

---

## Related Files

- `COORDINATE_SYSTEM.md` - Coordinate system documentation
- `ScreenshotPreviewView.swift` - Main UI implementation
- `ScreenshotPreviewController.swift` - Window controller
- `AnnotationModels.swift` - State models and enums
- `ElementRenderer.swift` - Renderer protocol and factory
- `MagnifierRenderer.swift` - Example renderer implementation
- `ScreenshotService.swift` - Screenshot capture service

---

## Version History

- **2025-12-26**: Initial architecture documentation
  - Documented current boolean state approach
  - Proposed enum-based state machine
  - Analyzed view hierarchy, cursor, event, and data flow
  - Documented decision points and relationships to coordinate system

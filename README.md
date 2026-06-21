# Memoria - visionOS Spatial Photo Gallery

> An **Apple Vision Pro (visionOS)** app that turns your photos into a spatial immersive experience.
> Your memories don't live in a flat gallery - they **orbit around you** inside a glowing glass
> cylinder that rises from the floor of your room.

Built at the **Apple Developer Academy**.

---

## The idea

You sit or stand at the center of the room. A luminous glass ring grows from the floor, three
meters tall, and your photos drift slowly around you across multiple orbits - like planets around
a star. Tap one and it flies in front of you; pinch and drag to hold it like a postcard; two-hand
pinch to scale it. Step inside the cylinder and the world fades to white, leaving you alone with
your memories.

---

## What it demonstrates

| Area | Skill shown |
|------|-------------|
| **Procedural geometry** | A hollow glass cylinder built from scratch with `MeshDescriptor` - vertices, normals, UVs and triangle indices for all 4 surfaces (no built-in primitive) |
| **ARKit on visionOS** | `ARKitSession` + `WorldTrackingProvider` (head position/orientation) + `PlaneDetectionProvider` (real floor) |
| **RealityKit** | `ModelEntity`, `PhysicallyBasedMaterial` (glass) / `UnlitMaterial` (glow), `Collision`/`InputTarget`/`Hover`/`Opacity` components, `move(to:)` animations |
| **Spatial gestures** | `DragGesture` / `MagnifyGesture` `.targetedToAnyEntity()` for tap, drag-to-hold and pinch-to-scale |
| **Swift Observation** | `@Observable` macro for reactive state without `@Published` |
| **Math (simd)** | Orbit transforms, look-at orientation toward the user's gaze, hysteresis for the inside/outside detection |

---

## What's in this repo

A **portfolio excerpt** - the three most interesting files, not the full app:

- [`GlassCylinderMesh.swift`](GlassCylinderMesh.swift) - procedural hollow-cylinder mesh (`MeshDescriptor`).
- [`EnvironmentTracker.swift`](EnvironmentTracker.swift) - ARKit head tracking + real-floor detection.
- [`MemoryRingSystem.swift`](MemoryRingSystem.swift) - the heart: orbits, white-world transition, and all the spatial gesture logic (grab, scale, select, place-in-front-of-gaze).

The UI shell (onboarding, home, photo picker, immersive view glue) is intentionally omitted.

---

## Requirements

- Xcode 16+, visionOS 2.0+
- Apple Vision Pro (or Simulator - real-floor detection is automatically disabled in the Simulator)

---

*Built with Swift, RealityKit, ARKit, visionOS - Apple Developer Academy project.*

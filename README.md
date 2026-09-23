# GoPro Fusion Stitcher

[![build](https://github.com/bangadrum/goprofusionstitcher/actions/workflows/build.yml/badge.svg)](https://github.com/bangadrum/goprofusionstitcher/actions/workflows/build.yml)

A small macOS app that stitches raw GoPro Fusion `GPFR####.MP4` / `GPBK####.MP4`
front+back fisheye video pairs into a single equirectangular (360°) video you
can drop straight into a DaVinci Resolve timeline and reframe — without
needing GoPro Fusion Studio (which is unmaintained, 32-bit-adjacent, and
increasingly broken on current macOS).

## How it works

The stitching method follows the approach built up across Trek View's
["Stitching GoPro Fusion Images Without GoPro Fusion Studio"](https://www.trekview.org/blog/gopro-fusion-fisheye-stitching-part-1/)
series (parts [1](https://www.trekview.org/blog/gopro-fusion-fisheye-stitching-part-1/),
[2](https://www.trekview.org/blog/gopro-fusion-fisheye-stitching-part-2/),
[3](https://www.trekview.org/blog/gopro-fusion-fisheye-stitching-part-3/),
[4](https://www.trekview.org/blog/gopro-fusion-fisheye-stitching-part-4/)),
and their [fusion2sphere](https://github.com/trek-view/fusion2sphere) tool's
parameter files, re-implemented as an ffmpeg filter graph rather than a
separate C stitcher, so the whole thing runs as one fast, hardware-friendly
pass per clip:

1. **Crop** — each fisheye circle (front and back have slightly different
   radius/center due to the offset lens mounts) is centered in a square crop,
   padded first since the circle extends a few pixels past the raw frame on
   some edges.
2. **Dewarp** — ffmpeg's `v360` filter remaps each 190°-FOV fisheye onto its
   own full equirectangular canvas: front centered at yaw 0°, back rotated to
   yaw 180°. Because each lens's FOV is >180°, the poles (zenith/nadir) are
   already fully covered by a single eye — no vertical gap.
2. **Blend** — the two eyes overlap by ~5° at each of the two side seams
   (yaw ±90°). A gradient mask feathers the transition across that overlap
   (full weight to whichever eye is more "on-axis", ramping to 0 across each
   seam) so the seam dissolves instead of hard-cutting.
4. **Encode** — the result is muxed with the front camera's audio track and
   encoded to your choice of ProRes 422 HQ, ProRes 422, DNxHR HQ, or H.264.

This was tested end-to-end against real GPFR/GPBK 5.2K sample footage before
being wired into the app — see the geometry constants and their provenance
in `Sources/GoProFusionStitcher/Models/CameraMode.swift` and
`Core/StitchFilterGraph.swift`.

**What this does *not* do**, compared to GoPro's own D.WARP: per-pixel optical
flow / parallax-aware blending, automatic exposure/color matching between the
two lenses, or horizon leveling. For footage without very close subjects near
the seam, the result is visually clean. For a subject inches from the seam
(like a selfie stick), you'll see the same ghosting any dual-fisheye stitch
produces — that's a parallax problem no 2D blend fully solves. Nothing about
reframing later in Resolve depends on this, since you're just panning/tilting
around the sphere.

## Requirements

- macOS 13 (Ventura) or later
- [Xcode Command Line Tools](https://developer.apple.com/xcode/resources/)
  (for `swift build` — full Xcode is optional but makes editing/debugging nicer)
- [Homebrew](https://brew.sh) `ffmpeg`: `brew install ffmpeg`
- Optional but recommended: `brew install exiftool` (embeds 360° metadata so
  Resolve/QuickTime auto-detect the clip as spherical)

## Build & run

```bash
cd GoProFusionStitcher
swift build -c release
swift run -c release          # launches the app directly, or:
```

To get a proper double-clickable `.app` you can drag into `/Applications`:

```bash
swift build -c release
./Scripts/make_app_bundle.sh
```

This produces `GoPro Fusion Stitcher.app` in the project root, ad-hoc signed
so Gatekeeper will run it (right-click → Open the first time).

Alternatively, open the folder in Xcode (`File → Open…`, select the folder —
Xcode reads `Package.swift` directly) and hit Run for the usual debug
experience with breakpoints, console, etc.

> **If Xcode's strict concurrency checking flags warnings/errors:** this
> project targets ordinary Swift 5 concurrency (not Swift 6 strict mode). If
> your Xcode defaults to Swift 6 mode and turns these into hard errors, set
> **Swift Language Mode → Swift 5** in the target's Build Settings.

## Using the app

1. Drag your `GPFR####.MP4` / `GPBK####.MP4` files (or a folder containing
   them) onto the window. They're paired automatically by take number.
2. Check the detected mode (3K or 5.2K) shown next to each clip.
3. Adjust settings on the right if needed — the defaults (ProRes 422 HQ,
   recommended output width for the detected mode, 5° blend) match what
   Fusion Studio itself would have used.
4. Click **Stitch All**. Progress shows per-clip; click a clip to see its
   live ffmpeg log.
5. Output lands next to the source files (or your chosen output folder) as
   `GP####_360.mov`.

## Bringing it into DaVinci Resolve

Import the stitched `.mov` like any other clip. Because it's a flat
equirectangular frame (2:1 aspect), Resolve's ordinary reframing tools work
on it directly:

- **Fusion page** → add a **3D Transform** or the **Camera 3D** node type is
  overkill; instead use the **Equirectangular** camera setting on a
  **Camera 3D** node feeding a **Renderer 3D**, or more simply drop
  **ResolveFX Warp → Camera-Wave/360** or Resolve's built-in **360-degree
  view** tools onto the clip if your Resolve version has them (Studio only).
- **Simplest option that works in every Resolve version:** treat it as a flat
  wide image and manually pan/crop/zoom with keyframed **Pan and Zoom** /
  **Transform**, since at this point it's just a normal video file — no
  special plugin required for basic reframing.
- If you enabled **spherical metadata embedding** in the app and have
  exiftool installed, Resolve (Studio) and QuickTime will recognize the clip
  as 360° automatically and give you the pannable viewer + Resolve's native
  360 reframe tools instead of the raw flat image.

## Third-party components

This app shells out to `ffmpeg` (GPL/LGPL, via Homebrew) and, optionally,
`exiftool` (Artistic/GPL, via Homebrew) — neither is bundled or modified, and
neither ships with this project. You must install them separately as above.

## Credit

Stitching geometry and approach based on Trek View's public blog series and
`fusion2sphere`'s parameter files (CC BY-SA 4.0 / documented open-source
project) — see the links above. This project is an independent
reimplementation as an ffmpeg filter graph with a native macOS GUI, not a
fork of their code.

# FIX-017: Rendered-chord dragging

The user reported unreliable Apple Pencil dragging in Select on a Rhythm Section
Sheet: gestures often did nothing, sometimes deleted a chord, and occasionally
worked. The connected app was iChart 1.2.4 (149). This focused patch is based on
that build's source commit, `d8774fa7cdeb2270d169200e14d2a09264335cd5`.

## Change

Chord controls retain their generous hit areas but sit outside the visible chord
body. Padded controls also exclude neighboring chord bodies. At the canvas edge, the width handle uses the clear row above the chord so its full target remains reachable. A body drag in
Select selects and moves the chord in one gesture. The canvas retains the exact
touch-down position, target ID and action through pan startup, so admission and
startup use the same target. Movement accumulated before `.began` appears at once.
The former 1.5-second post-render Select lockout is removed.

Tap recognizers wait for movement to fail. A chord delete requires the same
explicit X at touch-down and lift, no recognized or cancelled drag, and movement
within four screen points for Pencil or six for other input. Delivered and
coalesced movement samples cancel deletion once that tolerance is exceeded;
returning to the start cannot revive it. The next ordinary X tap remains usable.

During movement, a transient layer renders the selected chord once and updates
its position and beat guides. The canvas redraws its backing at the beginning
and end, rather than for every movement event. The glyph keeps its chosen width
at measure edges. The existing cached destination, snap policy and single model
commit on lift remain in use.

Cancellation, mode changes, suspension, app deactivation, window removal, bounds
changes, chart switching and removal of the active chord clear the temporary
preview. Original source ink stays with the moved chord. Select's quick helper
and How To describe direct drag/lift, explicit red-X deletion, the width
handle and double-tap correction together.

## Validation

On a dedicated iPad Air (4th generation) Simulator with iPadOS 26.5, the focused
native gate passed **120 tests, zero failures, zero skips**. The tests exercise:

- Pencil-typed touch admission through actual canvas pan startup, movement and
  commitment for narrow C/G chords in Rhythm and Simple layouts.
- Immediate movement after rendering, retained gesture ownership, safe body
  taps, body-to-X movement, X drift and out-and-back movement, then valid deletion.
- Explicit width resizing, chord correction, drag/tap exclusivity, cancellation,
  mode/bounds changes and late callbacks.
- Sixty host preview updates per style with one cached glyph, no backing
  invalidation, no chart writes and preserved glyph width; standalone layer
  reuse, screen scale, guides, cleanup and hit passthrough.
- A nonempty PencilKit source archive retained byte-for-byte after movement and
  chart encode/decode reopening, plus existing targeting, snapping, ending,
  articulation and scroll controls.
- Direct-drag guidance in both styles and readable Select help at normal and
  largest text sizes in a narrow hosted view.

Captured Simple/Rhythm movement previews showed one moving chord with placement
guides and no duplicate backing glyph. The Select helper remained readable with
its Guide action reachable. Independent source review found no remaining
actionable finding in the patch.

These are native controlled-input and captured-view results. Fresh physical
Pencil feel, real event timing and device retest remain a separate acceptance
gate. No model schema, recognition, or musical-placement rule changed.

## Device handoff

Build 151 (1.2.4) was installed in place after the user confirmed current writing
and review text were saved. Two fresh stopped-app backups matched exactly.
Before-first-launch and independent stopped postlaunch comparisons preserved the
saved charts, source/page/header ink, PDFs, setlist, correction/profile files and
intentional deletions. Normal startup metadata was classified with fresh
snapshot-bound evidence; no older library was restored. The retired diagnostic
checkpoint retained its original bytes and existing stale binding.

The app was normally reopened and left running. This confirms installation,
startup and saved-data preservation. Fresh physical Pencil acceptance remains
pending the user's direct chord-drag retest.

# Rhythm Recognition Visual References

These files are backend recognition references, not user-facing app assets.

## Stored Sources

- `simple-rest-and-rhythm.jpg`
  - Source: user-provided upload, 2026-06-22.
  - Scope: single note/rest symbol chart.
  - SHA-256: `5d52a9813ea0b2f9cbfb6d40d9a03cbfbe2807b67b1d6729dd1307ceb3b3d901`
  - Note: the image appears to label dotted quarter as `1/2` beat; iChart reference metadata treats dotted quarter as 1.5 quarter-note beats.

- `rhythm-combinations.pdf`
  - Source: user-provided upload, 2026-06-22.
  - Scope: 5-page rhythm combination reference.
  - SHA-256: `81ef85d33af677cd9d1340faebe42716b189911e22acad75a5d8ba684720c787`

## Use

Use these files as visual cross-reference material when building fixture prompts, reviewing recognizer classifications, and validating rhythm-context rules. Do not bundle them into the production app or expose them in Help unless the product direction changes.

See `../visual-ink-reference-bridge.md` for the backend connector that translates raw ink shapes into visual tokens, handwritten symbol abstractions, and rhythm-combination context.

See `../recognizer-decision-contract.md` and `../golden-fixture-matrix.md` before changing recognition behavior. The contract defines the required recognizer output surface, and the fixture matrix defines the examples that must commit, preserve ink, or refuse auto-render.

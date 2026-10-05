# Preserve learned handwriting while adding missing symbols

The fixed mixed-source continuation improved HASY symbol coverage, but reduced
UJI generic/personal development reads and introduced a Simple-sheet regression
on seen private ink. It is not promoted. The next experiment changes only how
the missing shared symbols are learned, not the data, glyph grouping or grammar.

Freeze the original visual encoder, BatchNorm state, projection and all 97
classifier rows at weights SHA-256
`5cddc61266d283af28eecfba3bbd8ec6a5b4e396e36b2dba8751b93c880d70a0`.
Train only five additional linear output rows for `#`, `+`, `/`, `ø`, `△`.
Use the pinned sources, exact bitmap mapping/normalization, fold-1 exclusions,
32/8 UJI writer split and untouched 20 reserved writers from
`personal-symbol-training-protocol-2026-09-28.md`.

Fit on all eligible source training images. Original logits are fixed competing
outputs, so old examples act as negatives for the new classes. Class-balanced
102-way cross-entropy plus 0.0001 times the mean squared new weight; no penalty
on biases. Full-batch double-precision L-BFGS, lr 1, maximum 200 iterations and
400 evaluations, strong-Wolfe search, gradient tolerance 1e-7 and change
tolerance 1e-10. Initialize new weights to zero and biases to -5. No geometric
augmentation in this convex output-only fit. No parameter/checkpoint selection
from development or private predictions. Convert only the final new rows to
float32 and evaluate that exact saved model.

Preserving old weights does not guarantee old answers: a new class can still
outscore an old class. Measure and report such substitutions. Original features
must be unchanged; old logits must agree within 1e-4 for all 1,552 UJI development
samples (wider GEMM can change float32 accumulation order).

Public anchors preserve the original 97 UJI-training means and add only the
five means from HASY training for the new classes. Keep explicit personal
learning unchanged and compare both 16-lesson and 97-lesson profiles. Report
gains/harms and symbol substitutions, not just means. Evaluate HASY separately:
its IDs do not establish writer independence, and its ODbL dataset license does
not establish shipping eligibility. No private input is used for fitting the
shared model; local replay follows public evaluation, using unchanged confirmed
personal examples and raw top-one composition only. No engine substitution or
app deployment is included.

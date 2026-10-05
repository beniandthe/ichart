# Personal learning with a shared-shape preservation prior

Frozen follow-up to `personal-adaptability-training-protocol-2026-09-28.md`.
The sparse-profile result showed zero harms on taught labels but 29 harms on
untaught labels with the starting model; additional personalization training
still had 24 untaught harms. Do not adopt that trained candidate or change its
settings after results. Investigate the missing constraint in the personal fit.

## Fixed experiment, before new predictions

- Reuse the **original** frozen visual encoder and weights SHA-256
  `5cddc61266d283af28eecfba3bbd8ec6a5b4e396e36b2dba8751b93c880d70a0`,
  not whichever retrained model happens to score highest. Do not retrain it.
- Use only the same 32 training writers to form one generic feature anchor per
  character: average all original (not augmented) unit embeddings of that label,
  then unit-normalize the mean. These anchors represent public training shapes,
  not personal examples or labeled development queries. Fail on an invalid mean.
- Fit the same class-balanced residual to explicitly labeled personal examples,
  with lambda 0.1, plus a unit-weight, zero-correction constraint at each anchor
  whose label is **absent** from the personal lessons. With `X` the balanced
  personal features, `R` the balanced personal residual targets and `A` those
  remaining anchors, solve
  `(X^T X + A^T A + 0.1 I) W = X^T R`.
- Each untaught label contributes exactly one anchor. No scalar sweep, hand-picked
  symbols, generic-score threshold, expected-answer selection or per-writer rule.
  Predictions remain `softmax(queryLogits) + queryFeatures W`, uncalibrated ranks.
- An empty profile must leave generic predictions unchanged. A profile covering
  the entire generic vocabulary must reproduce the existing residual learner.
  Explicit novel symbols are permitted but get no invented generic training data.
  Anchors are separate from explicit lessons, never saved as user handwriting.
- Evaluate the same fixed sparse16 and full97 profiles and exactly the same
  eight writers/session-two inputs/novelty exclusions as the preceding run.
  Preserve all97 competitors, all failures, per-writer and taught/untaught counts.
  This remains inspected development evidence, not independent-writer validation.
- Verify the independent closed-form equations, empty/full profile limits,
  explicit-label correction, class balance, input immutability, label-order
  independence and query-answer isolation. Bind the report to encoder/source,
  anchor data, frozen protocol, implementation and prior result hashes.

This regularized personal-learning experiment does not change the live app or
the comparison model loader. A successful character result would still require
Swift/Core ML parity and full-chord/symbol/fresh-handwriting evaluation before
promotion. The same musical-symbol coverage limitations apply. A negative result
must remain visible; do not weaken the comparison until it appears positive.

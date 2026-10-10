# Local personal learning with the existing shared-shape constraints

Fixed follow-up before new predictions. The local residual experiment passed
its larger-profile comparison (639/772 versus 628/772) but failed the
small-profile harm gate (seven versus five generic-correct reads lost). Its
report and width artifact are preserved under SHA-256
`739b2b7c7d408bddb0a6b8f21dc09a9e23fc6266a18b65d8dc6f67230804f660`
and `33ed8df132011bbec26ceb419d7c0dc71aaaf6a257d0330461a260dd1348471e`.
It is not promoted. This follow-up tests one additional existing constraint,
not a width/regularization search or a private-chord-specific repair.

Reuse the original visual encoder, lambda 0.1 and the frozen training-pair
width **0.16684838059285878**. Reuse the exact public mean-shape anchor bank from
the earlier linear-anchor experiment, bound to its source and encoder hashes.
Append each untaught generic class's anchor as a unit-weight **zero-residual**
constraint in the kernel fit. Personal examples retain per-label class balance.
Anchors are not user labels, profile examples or fabricated training answers.

The augmented kernel is computed over personal examples plus untaught anchors;
the target matrix is personal residuals plus zero rows. Solve the same weighted
dual equation. Empty profiles remain generic; full-vocabulary profiles have
no untaught anchors and must exactly reproduce the existing local learner.
Validate the independent weighted equations, duplicate balance, prior-order
invariance and explicit novel labels before evaluation.

Keep all original splits, query identities and copy exclusions. Report all
772 eligible development characters for both frozen sparse16 and full97
profiles, with per-writer and taught/untaught outcomes. Compare gains and harms
against generic, original linear, linear-anchor and unanchored-local results.
No private input or reserved writer is used.

The next-step gate is unchanged in spirit and not weakened: sparse correct
count at least 614, full correct count at least 639, and sparse harms against
generic at most five. A pass permits only comparison-path implementation;
full-chord, musical-symbol, new-handwriting, independent-writer and trust gates
remain open. No live recognition or profile modification is authorized by a
positive development result. Preserve all failures and repeat for determinism.

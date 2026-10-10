# Pure profile count and trained-action updates

These new static ARM64 body captures share the pinned CortexService binary hash.
No Cortex execution/profile/model assets are bundled. ReferenceTrainingProfileUpdates
is comparison-only; hardware acquisition, UI, manager persistence and production inference
remain unchanged. Its catalogue/action mapping is supplied explicitly by the caller.

## Count update: property absence matters

countNumberOfTimesTraining at0x100b33890 reads
cognitiv-numberOfTimesActionTraining. If present, rows must be1 (3398c..33994)
and columns equal the global action catalogue size (3399c..339ac). The manager
ordered-map lookup resolves actionID to count column (339b0..33c48). The selected
count increases by1 at33c54..33c64, then the property is stored at33cac.

If counts are absent, 33a3c..33a50 creates1xN zeros. The trained-actions property
is checked separately at33a54..33ab4:

- If trained-actions exists, getTrainedActions returns IDs. The manager map is
  traversed in key order and each mapped ID present in that list is assigned1,
  except the current action gets2 (33b24..33b3c vs33b58..33b64). If current action
  is not listed, its count remains0; do not silently replace this with1.
- If trained-actions does not exist, the current mapped column gets1 at
  33d18..33d2c. Both paths store the resulting property at33d60.

Our bounded contract supplies unique nonnegative actionColumns explicitly; each
index is the caller-observed column mapping. It excludes unknown IDs and ambiguous
map collisions. The vendor map can insert missing keys with value0; that unvalidated
case is not fabricated. maximumActions is an independent resource policy. Finite
nonnegative count checks and rejection when +1 cannot increase a binary64 value are
our numerical support policies, not recovered vendor validation defaults.

## Trained action update: DB flags and stable reconciliation

updateTrainedSigActions copies the global catalogue in order (33f40..340e4), then
GaussianDatabase::isClassesDataExist produces bool flags (340e8..340f8).
3413c..34184 tests each flag and appends the matching catalogue ID. Existence is
supplied as an explicit boolean input; it is not inferred from counts or EEG quality.

341a8 reads the old trained IDs. The helper372e8 receives profile,key,new-list,old-list.
Its full named capture is in counts-reconcile.txt:

- 37338..373dc walks old IDs, erasing those absent from new-list; survivors retain
  original order and duplicate entries.
- 373dc..37470 walks new-list in order and appends an ID only if not already in
  the retained old-list.
- 37470..37568 allocates1xK matrix when nonempty; 37540..37554 casts IDs as
  unsigned32 to binary64. Empty result remains an empty matrix.
- 37574 stores the matrix under cognitiv-trainedActions.

The pure helper produces the reconciled ID list. It does not fake database existence,
export a vendor profile, claim the database load path is recovered, or deduplicate
old surviving entries differently from the body. Nonnegative Int32 IDs are our
supported domain; unknown global values remain explicit caller prerequisites.

## Sensitivity table loading boundary

loadSensitivityFromConfig at0x100b3922c clears manager+b90 (39240..39244),
normalizes headset type (3924c), searches the keyed config map rooted at+b88
(39250..392b4), then copies the matching list into+b90/+b98/+ba0
(392b8..392d8). No match leaves it empty, selecting exp10 in getCurrentClassWeights.
The list's source config-loading implementation and actual per-headset values are
still unresolved. No learned priors are implied and no ten-entry table is invented.

## Verification gates

Five analytic tests cover present counts, absent property branches, current-unlisted
zero behavior, stable ordering/duplicate preservation, empty availability, malformed
inputs and explicit capacity bounds. No matched profile outputs exist; these are
not same-profile Cortex parity passes. Our catalogue and DB flags must be validated
against actual reference inputs before claiming manager-level parity.

Validation command: `swift test --package-path apple --filter ReferenceTrainingProfileUpdatesTests`: 5 tests, zero failures.

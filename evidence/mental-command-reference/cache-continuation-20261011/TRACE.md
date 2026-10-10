# Classifier cache pure semantics and manager boundary

Static ARM64 named bodies and helper bodies are captured in cache-bodies.txt and
cache-helpers.txt from the pinned executable. No database, model, binary or credential
assets are bundled. ReferenceClassifierCache stores explicit caller-supplied payloads;
it is comparison-only and does not replace live acquisition or inference.

## Key and exact vector validation

get/put pass separator comma ASCII44 to helper260fc (26304..26318,
2645c..26470). Helper261a4..26218 walks supplied int32 actions in original order,
streams each as decimal signed int (261cc), and inserts separator only between
elements (261dc..26204). No sort or deduplication occurs. Empty vector gives empty
key. get searches map via2685c (26334), then requires cached classifier action-vector
byte count and memcmp equal to the requested vector (26370..2638c). put validates
non-null classifier and exact action vector before inserting (26424..26450).
Our typed Entry requires the same actions; impossible/null payload cases are outside
this API and mismatches throw rather than abort. Keys contain only ASCII decimal,
minus and comma, so Swift string sort preserves the reference byte ordering.

## Enabled state, sizing, replacement and eviction

- Constructor26060..26078 sets enabled true, maximum size0, empty ordered map.
- setEnabled26090 stores bool; false clears the tree (2609c..260ac). true retains
  existing entries. get disabled returns null (262ec..262f0,263a0); put disabled
  returns false before checking payload/actions (26418..2641c,264e0..264e4).
- setMaximumCacheSize stores size at+8 and clears the whole tree unconditionally
  (260d0..260e4), even if size is unchanged or0.
- put existing key bypasses capacity eviction (26494..264c0), replaces shared
  pointer at node+38. New key reads max size;0 bypasses vendor capacity cap;
  otherwise when current size>=max it chooses a victim before insertion
  (264fc..2650c).
- Victim begins at map begin (lexicographically smallest key). Traversal reads
  classifier UInt64 field+0x460; csel at26580 changes candidate only if current
  candidate value>visited value. Thus minimum field wins; ties retain first key.
  26554..26558 erases victim, then inserts new entry.
- removeDirtyClassifier has no enabled gate.266e4..26724 scans every classifier's
  action vector and deletes entries containing the supplied action; others remain.

The pure model has caller-provided storageLimit as an independent safety bound
for the vendor's unlimited-size0 case. Crossing it fails atomically; it is not a
recovered vendor cap. Payload ownership/reference-count/destructor behavior is not
reproduced; the generic payload is explicit data, not a mock trained classifier.

## Field+0x460 and manager sequencing

Complete manager body is maintained in
../training-lifecycle-continuation-20261011/lifecycle-bodies.txt:

- buildClassifier2f76c checks enabled. If rebuilding (boolean parameter),
  removeDirtyClassifier2f7d0 runs for current action before get2f820.
- Hit2f874..2f87c adds1 to cached classifier field+0x460, then copies classifier
  at2f884. get itself has no frequency update. recordReuse separately models
  manager increment with UInt64 wrapping, not a timestamp/LRU update.
- Miss follows GaussianDatabase.loadClassesData2fabc, addUpdate2fd4c and
  (when indicated by manager branch) GaussianDatabase.saveClassesData2ff94.
  GaussianTraining.run301e8 fits the output. Successful new classifier resets
  field+0x460 to0 at302d4, copies output302dc, then puts if enabled3031c.
- Classifier.saveClassifier in training acceptance is a separate caller
  (335c0/3362c); cache puts do not serialize profiles or prove persistence.

These call sites establish a reuse-frequency eviction interpretation. Tracing every
other potential writer to this field remains outside the pure cache boundary.
No DB key encryption/schema/version, QSharedPointer ownership, threading or system
persistence guarantee is invented. The cache is not a replacement for those contracts.

## Validation boundaries

Analytic tests cover ordered/duplicate keys, exact vector mismatch, frequency eviction,
lex tie choice, no frequency change on get, existing replacement without eviction,
clear-on-disable/size, disabled put, dirty-action removal, wrap and explicit safety cap.
No matched vendor cache/profile observation exists; these tests establish the
implemented model semantics rather than claim end-to-end parity.

Validation: `swift test --package-path apple --filter ReferenceClassifierCacheTests`: 6 tests, zero failures.

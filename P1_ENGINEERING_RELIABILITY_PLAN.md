# P1 Engineering Reliability Plan

## Purpose

P1 converts the accepted P0 historical baseline into a safer, easier-to-run, diagnosable engineering workflow without changing DeepFaceLab model mathematics, checkpoint formats, merger behavior, or DFM semantics.

The accepted P0 reference is:

```text
Machine: rtx5880-ada
Environment: legacy-dfl-rtx3000-20211120
Model: p0gate_SAEHD
Iteration: 4
DFM SHA-256: E2F7E8810384FCE392DA0FA8D036795A93282C223E743855E5BCCB1EF22047C8
VisoMaster Fusion commit: 560c7645d63c07526fe7109fce6abcabf95768fa
```

P1 must not invalidate this reference. Any change affecting training, checkpoint loading, merging, export, or consumer compatibility requires a separate regression run against the P0 gates.

## Safety boundary

P1 implementation and CI must be able to run without:

- private or public face media;
- aligned face datasets;
- checkpoints or model weights;
- DFM files;
- biometric embeddings;
- a GPU;
- the historical DeepFaceLab runtime;
- VisoMaster Fusion;
- paid services.

Tests may use small synthetic text/JSON fixtures and temporary directories only.

## P1 workstreams

### P1.1 — Repository privacy and boundary validator

Create a CPU-only validator that fails closed when the repository or staged changes contain prohibited content or unsafe paths.

Required checks:

- known private-media extensions under repository paths;
- checkpoint, DFM, embedding, archive, credential, and local profile patterns;
- tracked files under ignored local directories;
- accidental absolute local paths in committed machine-readable fixtures;
- oversized binary files;
- suspicious generated output directories;
- clean and stable exit codes.

Output:

- human-readable summary;
- machine-readable JSON report;
- stable failure codes;
- no file modification except an explicitly selected artifact directory.

### P1.2 — Report schema and consistency validation

Define versioned schemas for P0/P1 reports and validate existing local reports without reading media or model contents.

Initial coverage:

- system diagnostics;
- historical runtime probe;
- Python layout inspection;
- TensorFlow/GPU visibility;
- dataset preflight;
- workspace preparation;
- extraction;
- initial training/save;
- resume;
- merge;
- DFM export;
- VisoMaster Fusion acceptance.

Required behavior:

- detect missing required fields;
- distinguish absent, stale, blocked, failed, and passed states;
- validate cross-report identity, machine, environment, model, iteration, path, and hash references;
- reject impossible state transitions;
- emit actionable remediation text.

### P1.3 — One-command acceptance summary

Add one Windows entry point that summarizes the current machine/profile and existing reports.

The command must:

- run PowerShell 5.1 compatible code;
- never start training, extraction, merge, export, or VisoMaster;
- never read image pixels, checkpoints, or DFM bytes unless an explicit integrity mode is selected;
- identify the latest report for each phase;
- print a compact stage table;
- write a versioned JSON summary;
- return nonzero only for defined blocking conditions.

### P1.4 — Structured failure taxonomy

Introduce stable failure categories shared by scripts and validators.

Minimum categories:

```text
configuration
missing_dependency
missing_prerequisite
path_boundary
privacy_boundary
repository_dirty
schema_invalid
state_inconsistent
process_start
process_timeout
process_exit
output_missing
output_unexpected
integrity_mismatch
checkpoint_invalid
checkpoint_corrupt
rollback_failed
unsupported_environment
manual_review_required
```

Each failure must include:

- code;
- phase;
- concise message;
- evidence path when safe;
- remediation action;
- whether retry is safe;
- whether local state may have changed.

### P1.5 — Checkpoint backup and recovery design

Document and implement safe model-state operations before adding broader automation.

Required design properties:

- read-only inventory before mutation;
- SHA-256 manifest;
- temporary clone or staging directory;
- atomic replacement only after validation;
- retained rollback copy until post-commit verification;
- deterministic cleanup rules;
- detection of missing, truncated, mismatched, or unpicklable checkpoint files;
- explicit recovery decision report;
- no in-place repair without a verified backup.

The accepted P0 eight-file checkpoint layout is the initial fixture boundary, but actual checkpoint files remain local and are never used in CI.

### P1.6 — CPU-only tests and CI

Add tests for all logic that does not require the historical runtime or GPU.

Initial test set:

- PowerShell parsing and parameter validation;
- JSON schema fixtures;
- report ordering and latest-report selection;
- path normalization and containment;
- privacy pattern detection;
- failure-code mapping;
- temporary staging and rollback simulations;
- interrupted write simulations;
- corrupted JSON and truncated manifest fixtures;
- Windows path edge cases;
- no-secret and no-private-artifact repository checks.

CI must:

- run on pull requests to `develop`;
- avoid downloading model files or GPU packages;
- avoid paid services;
- produce test summaries and safe artifacts only;
- complete within a bounded time.

### P1.7 — Documentation and release readiness

Update:

- contributor guide;
- Windows setup guide;
- local profile guide;
- troubleshooting guide;
- security and responsible-use guide;
- report schema reference;
- backup and rollback guide;
- release checklist;
- migration notes.

## Implementation slices

### Slice A — Static reliability foundation

- repository privacy validator;
- report schema definitions;
- JSON fixture tests;
- stable failure-code module;
- CPU-only CI.

No historical runtime execution is allowed in Slice A.

### Slice B — Read-only local acceptance summary

- one-command summary BAT/PowerShell entry point;
- latest-report discovery;
- cross-report consistency checks;
- local profile summary;
- JSON and console output.

No model or DFM modification is allowed in Slice B.

### Slice C — Backup and recovery primitives

- checkpoint inventory API;
- verified staging copy;
- atomic swap primitive;
- rollback primitive;
- simulated interruption tests;
- corruption classification.

No automatic repair of real checkpoints is enabled until the simulated tests pass.

### Slice D — Controlled integration

- adopt common failure codes in existing P0 scripts where safe;
- preserve legacy-compatible behavior;
- run selected P0 regression gates only when a change touches their boundaries;
- document rollback to the accepted P0 branch/commit.

## P1 acceptance gates

### Gate P1-A — Static validator accepted

Pass when repository/privacy validation and report-schema tests run CPU-only with deterministic results and no prohibited files are committed.

### Gate P1-B — One-command summary accepted

Pass when one command can summarize a clean machine with no reports, a machine with partial reports, and a machine with a complete P0 report chain without starting any runtime action.

### Gate P1-C — Recovery primitives accepted

Pass when temporary synthetic checkpoint fixtures survive success, interruption, corruption, rollback, and cleanup simulations without losing the last accepted state.

### Gate P1-D — CI accepted

Pass when pull-request CI runs all CPU-only tests, privacy checks, and schema checks within the defined time and produces no sensitive artifacts.

### Gate P1-E — Documentation accepted

Pass when a new contributor can understand setup, profiles, reports, failure codes, backup, recovery, and rollback without access to private media or local model files.

## P1 exit condition

P1 is complete only when:

- one-command diagnostics and acceptance summary exist;
- report schemas and failure codes are stable and tested;
- privacy and repository boundaries fail closed;
- checkpoint backup/rollback primitives pass simulated failure tests;
- CPU-only CI protects `develop`;
- contributor, troubleshooting, security, and release documentation are current;
- no regression has been introduced into the accepted P0 workflow.

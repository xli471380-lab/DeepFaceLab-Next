# P0 Authorized End-to-End Test Plan

## Purpose

This plan validates the frozen historical DeepFaceLab runtime on authorized, non-public test media before P0 is accepted.

The required workflow is:

1. dataset preflight and immutable local manifest;
2. destination/source frame extraction;
3. face extraction and alignment;
4. a deliberately short training run;
5. explicit save and clean exit;
6. resume from the saved checkpoint;
7. merge a short destination segment;
8. export a DFM model;
9. load the DFM model in VisoMaster Fusion;
10. record reports, hashes, logs, and acceptance decisions.

## Authorization and privacy boundary

- Use only media the operator owns or is authorized to process.
- Keep all faces, videos, images, aligned sets, checkpoints, merged outputs, and DFM files local and outside Git tracking.
- Do not use public figures, third-party identities, scraped media, or private media without permission.
- Do not upload dataset media, aligned faces, checkpoints, DFM files, or output videos to the repository or development chat.
- Reports may contain local paths and hashes but must not contain image pixels, face embeddings, or biometric templates.

## Stage 11 — Dataset preflight

The preflight must complete before any media is copied into the historical workspace.

Required evidence:

- separate source and destination identities;
- explicit authorization confirmation;
- source and destination paths are distinct;
- media paths are outside the Git repository, historical runtime, and historical workspace;
- recognized media files are present;
- file count and total-size limits are respected;
- SHA-256 is recorded for each input file;
- read-only media metadata is collected where `ffprobe` is available;
- repository working tree is clean;
- historical workspace snapshot is unchanged.

The preflight does not detect faces, extract frames, copy media, import TensorFlow, execute DeepFaceLab, or modify the workspace.

## Dataset size for the first P0 run

Prefer a deliberately small test set:

- source: one short clip or a small image set;
- destination: one short clip or a small image set;
- clear, consented adult subjects;
- stable lighting and mostly frontal or moderate-angle faces;
- no confidential background information;
- enough variation to exercise extraction without turning P0 into a quality benchmark.

The first run is a compatibility and reproducibility test, not a production-quality model.

## Execution gates

### Gate A — Dataset accepted

Pass only when the stage-11 manifest status is `passed`, authorization is confirmed, paths are isolated, files are hashed, and workspace/repository checks pass.

### Gate B — Extraction accepted

Pass only when frame extraction and face alignment finish without crashes, reports contain counts, failures are reviewed, and no unrelated workspace path changes occur.

### Gate C — Short training accepted

Pass only when the selected model initializes on the intended GPU, completes a bounded number of iterations, saves a checkpoint, and exits cleanly.

### Gate D — Resume accepted

Pass only when the saved checkpoint is discovered and training resumes with increasing iteration state rather than starting a new model.

### Gate E — Merge accepted

Pass only when a short destination segment is merged successfully and output file hashes and media metadata are recorded.

### Gate F — DFM accepted

Pass only when DFM export succeeds and the resulting local DFM file can be opened by VisoMaster Fusion without conversion or manual patching.

## Initial limits

The first run should be conservative:

- one GPU only;
- no system Python or system CUDA substitution;
- historical bundled runtime only;
- no dependency upgrades;
- no training automation without a stop condition;
- no long unattended run;
- no full-length source or destination video;
- no quality tuning until save/resume, merge, and DFM loading are proven.

## P0 acceptance

P0 remains active until all gates pass on at least one documented local profile. TensorFlow import and GPU visibility alone are necessary but not sufficient.

# P0 Reproducible Baseline Protocol

## Purpose

P0 establishes a trustworthy historical baseline before any runtime or algorithm modernization. It must answer one question:

> Can the inherited DeepFaceLab implementation complete a minimal, documented, repeatable end-to-end workflow on the maintainer's Windows/NVIDIA machine?

This protocol uses only media for which the operator has explicit permission. Private images, videos, face sets, embeddings, checkpoints, and exported identity models must not be committed to Git.

## Frozen source baseline

- Repository: `xli471380-lab/DeepFaceLab-Next`
- Upstream: `iperov/DeepFaceLab`
- Source commit: `e4b7543ffa1d73b26fce1e31852727f658ba490c`
- Development branch: `agent/p0-reproducible-baseline`

P0 does not change training logic, checkpoint formats, model architecture, merger behavior, or DFM export logic.

## Required evidence

Store redacted evidence below `artifacts/p0/` locally. The directory should contain no biometric media or trained identity model.

Required machine-readable files:

- `system-diagnostics-<timestamp>.json`
- `acceptance-summary-<timestamp>.json`
- `training-observation.json`
- `dfm-export-observation.json`

Screenshots may be kept locally but should be reviewed for private paths, faces, usernames, tokens, and other sensitive information before publication.

## Test dataset

Use a small authorized dataset that is sufficient to exercise the workflow, not to claim production quality.

Minimum coverage:

- Source face: front, left/right three-quarter, moderate expression variation.
- Destination face: a short clip with similar pose coverage.
- No minors, non-consenting people, private third-party media, or impersonation scenario.
- Keep the dataset outside the repository.

Record only non-identifying metadata:

- Source frame count.
- Destination frame count.
- Resolution ranges.
- Approximate pose coverage.
- Extraction detector and settings.

## Acceptance phases

### Gate 0 — Repository integrity

Pass conditions:

- Current repository and commit are recorded.
- Working tree changes are documented.
- Original GPL-3.0 license is present.
- No private dataset or model artifact is tracked by Git.

### Gate 1 — Machine diagnostics

Run:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\windows\system-diagnostics.ps1
```

Pass conditions:

- Windows version is captured.
- NVIDIA GPU and driver are captured.
- Available VRAM is captured when `nvidia-smi` supports it.
- Git, FFmpeg, Python launchers, CUDA tools, and relevant environment variables are recorded.
- The report is written successfully.

Missing historical runtime dependencies may be recorded as a P0 setup blocker rather than silently substituted with modern versions.

### Gate 2 — Face extraction

Pass conditions:

- Source video/images can be extracted.
- Destination video can be extracted.
- Face detection completes without an unhandled crash.
- Extracted faces can be reviewed and obvious false detections removed.
- Detector, face type, image size, frame counts, and elapsed time are recorded.

### Gate 3 — Short training run

This is a functional baseline, not a quality benchmark.

Pass conditions:

- A model can be created.
- Training reaches a predetermined small iteration target.
- Iteration time and peak VRAM are observed.
- Preview generation works.
- Loss values remain finite.
- The process can be stopped cleanly.

### Gate 4 — Save and resume

Pass conditions:

- Model files are saved.
- The process exits without corrupting the checkpoint.
- The same model can be reopened.
- Iteration count resumes rather than resets.
- A second save succeeds.

This gate is mandatory. A training process that only starts is not an accepted baseline.

### Gate 5 — Merge

Pass conditions:

- The destination clip can be merged using the trained model.
- Masks and color transfer execute without an unhandled crash.
- Output frames and final video are generated.
- Audio handling is documented.
- Output duration and frame count are checked against the input.

No claim of realism is required for P0.

### Gate 6 — DFM export

Pass conditions:

- Export completes without an unhandled exception.
- Exported file exists and has a non-zero size.
- Export settings, file hash, size, and elapsed time are recorded locally.
- The identity model itself is not committed.

### Gate 7 — Consumer validation

Preferred consumer: VisoMaster Fusion or another documented DFM-compatible runtime.

Pass conditions:

- The exported DFM is discovered by the consumer.
- It loads successfully.
- A short authorized preview runs.
- Execution provider, average processing speed, and visible failures are recorded.

## Failure classification

Use one of these categories:

- `environment_missing`
- `dependency_install`
- `gpu_runtime`
- `data_extraction`
- `training_start`
- `training_numerical`
- `checkpoint_save`
- `checkpoint_resume`
- `merge`
- `dfm_export`
- `consumer_load`
- `privacy_or_authorization`
- `unknown`

Every failure record should include:

- Phase.
- Exact command or UI action.
- Exit code when available.
- Relevant log excerpt.
- Environment report filename.
- Whether the failure is reproducible.
- Next diagnostic action.

## P0 exit criteria

P0 is complete only when all seven gates pass on one documented environment and the result is reviewed through a pull request.

A partial pass may be recorded, but it must not be described as a completed baseline.

## Modernization rule after P0

Any later dependency or algorithm change must be compared against this baseline for:

- Startup and extraction behavior.
- Training iteration speed.
- VRAM use.
- Numerical stability.
- Save/resume compatibility.
- Merge completion.
- DFM export and consumer loading.

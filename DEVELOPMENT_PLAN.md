# DeepFaceLab-Next Development Plan

## Mission

DeepFaceLab-Next is a maintained, testable, and reproducible continuation of DeepFaceLab. The project preserves the original person-specific training workflow and DFM ecosystem while improving Windows setup, diagnostics, modern NVIDIA GPU compatibility, reliability, and contributor documentation.

The frozen upstream baseline is `iperov/DeepFaceLab` commit `e4b7543ffa1d73b26fce1e31852727f658ba490c` (2024-11-13).

## Non-negotiable principles

1. Preserve original attribution and GPL-3.0 licensing.
2. Keep `master` as the historical upstream baseline until a reviewed release is ready.
3. Preserve existing model and DFM compatibility unless a migration path and rollback are documented.
4. Establish reproducible tests before changing training algorithms or dependency versions.
5. Never claim quality, speed, or compatibility improvements without recorded evidence.
6. Support only authorized, consensual, and clearly disclosed synthetic-media use.
7. Never commit private media, aligned faces, checkpoints, DFM files, embeddings, credentials, or local machine artifacts.

## Branch model

- `master`: protected historical upstream/release baseline.
- `develop`: reviewed integration branch.
- `agent/*`: scoped implementation branches merged through pull requests.

Completed initial branch: `agent/p0-reproducible-baseline`.

Planned next branch after PR #1 is merged: `agent/p1-engineering-reliability`.

## Roadmap

### P0 — Reproducible historical baseline

Goal: prove that the inherited implementation can complete a minimal end-to-end workflow on a documented Windows/NVIDIA environment.

Required gates:

- Record OS, CPU, RAM, GPU, driver, CUDA, Python, FFmpeg, Git, and repository commit.
- Extract source and destination faces from a small authorized test dataset.
- Start a short training run and record its bounded result.
- Save, stop, reload, and resume the model.
- Merge a small destination set and review the outputs and masks.
- Export and structurally validate a DFM model.
- Load and execute the DFM model in VisoMaster Fusion.
- Store machine-readable reports without committing private media or trained identity data.

P0 explicitly does **not** upgrade TensorFlow, Python, CUDA, NumPy, OpenCV, or the model architecture.

Status: **completed on `rtx5880-ada × legacy-dfl-rtx3000-20211120` on 2026-07-21**. The four-iteration model proves compatibility and reproducibility only; it makes no quality claim.

### P1 — Engineering reliability

Goal: turn the proven historical workflow into a safer, easier-to-run, diagnosable engineering system without changing model mathematics or the historical runtime.

Required outcomes:

- One-command Windows diagnostics and acceptance orchestration.
- Reproducible environment manifests and dependency/file hashes.
- Structured logs, stable report schemas, and actionable failure classifications.
- Safe interruption, autosave, resume, backup, and corrupted-checkpoint recovery.
- CPU-only/no-GPU CI checks for parsers, validators, policy boundaries, and scripts.
- Contributor, release, security, migration, rollback, and troubleshooting documentation.

P1 must preserve the accepted P0 checkpoint, merge, DFM export, and consumer-compatibility boundaries.

### P2 — Modern NVIDIA compatibility

- Evaluate supported modern driver/CUDA combinations in isolated branches.
- Introduce newer runtime support without breaking the P0 baseline.
- Measure training speed, VRAM use, numerical stability, save/resume behavior, merge output, and DFM export.
- Maintain a tested compatibility matrix.

### P3 — Workflow improvements

- Dataset quality scoring and duplicate/outlier detection.
- Pose, expression, blur, resolution, and occlusion coverage reports.
- Better XSeg workflow and mask-quality checks.
- Training dashboard, progress history, ETA, and task queue.
- Safer model backup, comparison, and export workflows.
- Automated VisoMaster Fusion export validation where technically feasible.

### P4 — Optional algorithm research

Only after P0–P3 gates are stable:

- Optional PyTorch backend experiments.
- Modern identity, perceptual, gaze, occlusion, and temporal losses.
- Higher-resolution texture and detail paths.
- New inference/export formats alongside, not instead of, legacy DFM.
- Benchmarks against the frozen historical baseline.

## Release gates

A change that affects training, checkpoints, merging, or export must include:

- Reproduction steps.
- Environment information.
- Before/after metrics.
- Save/resume verification.
- Compatibility and rollback notes.
- Confirmation that no private datasets, faces, model weights, DFM files, embeddings, or credentials were committed.

## Current priority

1. Review and merge PR #1 into `develop` as the accepted P0 baseline framework.
2. Create `agent/p1-engineering-reliability` from the merged `develop` branch.
3. Begin P1 with a CPU-only repository validator and one-command acceptance orchestrator that can summarize existing P0 reports without touching media, checkpoints, DFM files, or the historical runtime.

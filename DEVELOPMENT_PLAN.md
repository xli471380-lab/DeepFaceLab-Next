# DeepFaceLab-Next Development Plan

## Mission

DeepFaceLab-Next is a maintained, testable, and reproducible continuation of DeepFaceLab. The project will preserve the original person-specific training workflow and DFM ecosystem while improving Windows setup, diagnostics, modern NVIDIA GPU compatibility, reliability, and contributor documentation.

The upstream baseline is `iperov/DeepFaceLab` at commit `e4b7543ffa1d73b26fce1e31852727f658ba490c` (2024-11-13).

## Non-negotiable principles

1. Preserve original attribution and GPL-3.0 licensing.
2. Keep `master` as the historical upstream baseline until a reviewed release is ready.
3. Preserve existing model and DFM compatibility unless a migration path and rollback are documented.
4. Establish reproducible tests before changing training algorithms or dependency versions.
5. Never claim quality, speed, or compatibility improvements without recorded evidence.
6. Support only authorized, consensual, and clearly disclosed synthetic-media use.

## Branch model

- `master`: protected historical/release baseline.
- `develop`: reviewed integration branch.
- `agent/*`: scoped implementation branches merged through pull requests.

Initial branch: `agent/p0-reproducible-baseline`.

## Roadmap

### P0 — Reproducible historical baseline

Goal: prove that the inherited implementation can complete a minimal end-to-end workflow on a documented Windows/NVIDIA environment.

Required gates:

- Record OS, CPU, RAM, GPU, driver, CUDA, Python, FFmpeg, Git, and repository commit.
- Extract source and destination faces from a small authorized test dataset.
- Start a short training run and record iteration speed and VRAM use.
- Save, stop, reload, and resume the model.
- Merge a short test clip.
- Export a DFM model.
- Load the DFM model in a supported consumer such as VisoMaster Fusion and record the result.
- Store machine-readable reports without committing private media or trained identity data.

P0 explicitly does **not** upgrade TensorFlow, Python, CUDA, NumPy, OpenCV, or the model architecture.

### P1 — Engineering reliability

- One-command Windows diagnostics and acceptance scripts.
- Reproducible environment manifests and dependency hashes.
- Structured logs and actionable error messages.
- Safe interruption, autosave, resume, backup, and corrupted-checkpoint recovery.
- CI checks that do not require a GPU.
- Contributor, release, security, and troubleshooting documentation.

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
- VisoMaster Fusion export validation.

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
- Confirmation that no private datasets, faces, model weights, or credentials were committed.

## Current priority

Complete P0 documentation and diagnostics, then run the first local baseline acceptance on the maintainer's Windows/NVIDIA workstation.
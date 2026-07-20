# DeepFaceLab-Next Progress

Last updated: 2026-07-20

## Project state

- Repository fork created: `xli471380-lab/DeepFaceLab-Next`.
- Upstream baseline preserved on `master`.
- Baseline commit: `e4b7543ffa1d73b26fce1e31852727f658ba490c`.
- Integration branch created: `develop`.
- Active branch: `agent/p0-reproducible-baseline`.
- Draft pull request: `#1 P0: establish reproducible baseline framework`.
- Current milestone: **P0 — Reproducible historical baseline**.
- Development uses a machine-profile × environment-profile matrix.

## Completed

- [x] Fork archived upstream repository.
- [x] Confirm repository ownership and push permissions.
- [x] Define branch strategy and staged modernization roadmap.
- [x] Freeze the upstream source baseline.
- [x] Add development plan, P0 protocol, security policy, diagnostics, and acceptance scaffold.
- [x] Open the first draft pull request into `develop`.
- [x] Fix PowerShell 5.1 empty-result, collection binder, native stderr, and Python probe issues.
- [x] Add ignored local machine/environment profile template.
- [x] Add profile-driven P0 runner and per-profile artifact directories.
- [x] Document the two-machine development workflow.
- [x] Create and run `hp-a2000 × system-py312` local profile.
- [x] Pass the P0 environment scaffold on `hp-a2000 × system-py312` at commit `9d6cc7b6494dcd3e0f75b60c395f976159470e60`.

## Verified profile result

### `hp-a2000 × system-py312`

Status: **environment scaffold passed**.

Observed:

- Windows 11 Pro build 26200; PowerShell 5.1.
- Intel Core i5-12500; approximately 16 GB RAM.
- NVIDIA RTX A2000; 5754 MiB VRAM from `nvidia-smi`.
- NVIDIA driver 581.80; compute capability 8.6.
- System Python 3.12.10 probe passed.
- Git and repository integrity checks passed.
- Working tree was clean.
- No workspace, artifacts, or DFM files were tracked.
- FFmpeg and `nvcc` were not available on PATH; these remain non-blocking for this system-profile diagnostic.

This result validates the engineering profile and scripts only. It is **not** the historical DeepFaceLab end-to-end baseline.

## Maintainer machine matrix

### `hp-a2000`

- Primary role: engineering, low-resource and PowerShell compatibility validation.
- Current profile: `system-py312` — scaffold passed.
- Future profile: `legacy-dfl-baseline` — not created yet.

### `rtx5880-ada`

- NVIDIA RTX 5880 Ada Generation; approximately 46 GB VRAM.
- Approximately 64 GB RAM.
- Known ComfyUI environment: Python 3.13 and PyTorch CUDA 13.
- Primary role: performance, full training, high-resolution testing and DFM export.
- Existing ComfyUI environment must remain separate from DeepFaceLab.
- System/profile diagnostic: pending.

## In progress

- [ ] Create an ignored local profile on `rtx5880-ada`.
- [ ] Run profile-labelled diagnostics on `rtx5880-ada`.
- [ ] Identify the exact historical runtime bundle or dependency environment for the first baseline.
- [ ] Select the first machine for the `legacy-dfl-baseline` profile.
- [ ] Prepare a small, authorized, non-public test dataset.
- [ ] Execute extraction, short training, save/resume, merge, DFM export, and VisoMaster Fusion loading.

## Next local acceptance work

1. On the RTX 5880 machine, clone or update the same branch.
2. Create a local profile describing its current system or ComfyUI environment for diagnostics only.
3. Run `scripts/windows/run-profiled-p0.ps1 -DiagnosticsOnly` and review the separated report directory.
4. Compare only hardware and runtime inventory; do not treat the ComfyUI environment as DeepFaceLab-compatible.
5. Identify a self-contained historical DeepFaceLab Windows runtime without reusing FaceFusion, VisoMaster, or ComfyUI environments.
6. Prefer the RTX 5880 machine for the first full training/export baseline unless the historical runtime cannot recognize the Ada GPU.
7. Use the A2000 machine as the fallback compatibility and low-VRAM validation machine.
8. Create a `legacy-dfl-baseline` profile and validate extraction, short training, checkpoint save/resume, merge, DFM export, and consumer loading.
9. Attach only redacted JSON reports and measured results to the P0 pull request.

## Known risks

- The inherited CUDA requirements pin old packages including NumPy 1.19.3, h5py 2.10.0, OpenCV 4.1.0.25, SciPy 1.4.1, TensorFlow GPU 2.4.0, and tf2onnx 1.9.3.
- Modern Python/CUDA upgrades may break binary compatibility, checkpoint behavior, numerical output, or DFM export.
- RTX A2000 has limited VRAM, so training settings must be conservative on that machine.
- The historical TensorFlow/CUDA stack may not recognize the RTX 5880 Ada without compatibility work.
- Windows build 26200 is newer than the historical runtime and may expose compatibility issues.
- The RTX 5880's existing Python 3.13/CUDA 13 ComfyUI environment must not be mistaken for a compatible DeepFaceLab environment.
- P0 cannot be accepted from import tests alone; a real save/resume and export workflow is required.

## Milestone status

| Milestone | Status | Exit condition |
|---|---|---|
| P0 Reproducible baseline | Active | End-to-end authorized test run and DFM load verified |
| P1 Engineering reliability | Not started | Installer, diagnostics, tests, logging, recovery |
| P2 Modern GPU compatibility | Not started | Validated modern runtime matrix without regressions |
| P3 Workflow improvements | Not started | Dataset, XSeg, queue, dashboard, export improvements |
| P4 Algorithm research | Not started | Benchmarked optional modern backends/models |

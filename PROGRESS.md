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

## Completed

- [x] Fork archived upstream repository.
- [x] Confirm repository ownership and push permissions.
- [x] Define branch strategy.
- [x] Define staged modernization roadmap.
- [x] Freeze the upstream source baseline.
- [x] Add development plan.
- [x] Add P0 baseline protocol.
- [x] Add Windows system-diagnostics script.
- [x] Add initial P0 acceptance scaffold.
- [x] Add security and responsible-use policy.
- [x] Open the first draft pull request into `develop`.
- [x] Clone the project locally and run the first system diagnostics pass.
- [x] Fix PowerShell 5.1 empty-result `.Count` handling in the acceptance script.
- [x] Improve native stderr and Python probe capture in the diagnostics scripts.

## First local diagnostics observation

Observed workstation profile:

- Windows 11 Pro, build 26200, PowerShell 5.1.
- Intel Core i5-12500, 6 cores / 12 logical processors.
- Approximately 16 GB system RAM.
- NVIDIA RTX A2000 with 5754 MiB reported VRAM.
- NVIDIA driver 581.80, compute capability 8.6.
- Git available.
- Python launcher reports Python 3.12.
- FFmpeg not found on system PATH.
- `nvcc` not found on system PATH.
- No system CUDA/cuDNN/TensorRT environment variables were detected.

These observations do not yet identify a compatible historical DeepFaceLab runtime. A self-contained historical Windows runtime may be preferable to modifying the system Python 3.12 installation.

## In progress

- [ ] Re-run diagnostics and the P0 acceptance scaffold after pulling the PowerShell 5.1 fixes.
- [ ] Capture the complete Python probe result.
- [ ] Identify the exact historical runtime bundle or dependency environment for the first baseline.
- [ ] Prepare a small, authorized, non-public test dataset.
- [ ] Execute extraction, short training, save/resume, merge, DFM export, and VisoMaster Fusion loading.

## Next local acceptance work

1. Pull the latest `agent/p0-reproducible-baseline` changes.
2. Re-run `system-diagnostics.ps1` and `p0-acceptance.ps1`.
3. Review the newest JSON reports and classify any remaining environment blockers.
4. Locate or install a self-contained historical DeepFaceLab Windows runtime without reusing FaceFusion or VisoMaster environments.
5. Prepare a small authorized test dataset outside the repository.
6. Validate extraction, short training, save/resume, merge, DFM export, and VisoMaster Fusion loading.
7. Attach only redacted JSON reports and measured results to the P0 pull request.

## Known risks

- The inherited CUDA requirements pin old packages including NumPy 1.19.3, h5py 2.10.0, OpenCV 4.1.0.25, SciPy 1.4.1, TensorFlow GPU 2.4.0, and tf2onnx 1.9.3.
- Modern Python/CUDA upgrades may break binary compatibility, checkpoint behavior, numerical output, or DFM export.
- RTX A2000 has limited VRAM compared with high-end training cards, so P0 settings must be conservative.
- Windows build 26200 is newer than the historical DeepFaceLab runtime and may expose compatibility issues.
- The repository contains large historical assets and takes substantial time and disk space to clone.
- P0 cannot be accepted from import tests alone; a real save/resume and export workflow is required.

## Milestone status

| Milestone | Status | Exit condition |
|---|---|---|
| P0 Reproducible baseline | Active | End-to-end authorized test run and DFM load verified |
| P1 Engineering reliability | Not started | Installer, diagnostics, tests, logging, recovery |
| P2 Modern GPU compatibility | Not started | Validated modern runtime matrix without regressions |
| P3 Workflow improvements | Not started | Dataset, XSeg, queue, dashboard, export improvements |
| P4 Algorithm research | Not started | Benchmarked optional modern backends/models |

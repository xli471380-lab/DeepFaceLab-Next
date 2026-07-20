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
- Development now uses a machine-profile × environment-profile matrix.

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
- [x] Fix PowerShell 5.1 empty-result and collection binder failures.
- [x] Fix native stderr and Python `-c` argument handling on Windows PowerShell 5.1.
- [x] Add ignored local machine/environment profile template.
- [x] Add profile-driven P0 runner and per-profile artifact directories.
- [x] Document the two-machine development workflow.

## Maintainer machine matrix

### `hp-a2000`

- Windows 11 Pro build 26200; PowerShell 5.1.
- Intel Core i5-12500; approximately 16 GB RAM.
- NVIDIA RTX A2000; 5754 MiB VRAM from `nvidia-smi`.
- System Python 3.12; FFmpeg and `nvcc` not on PATH.
- Primary role: engineering, low-resource and PowerShell compatibility validation.

### `rtx5880-ada`

- NVIDIA RTX 5880 Ada Generation; approximately 46 GB VRAM.
- Approximately 64 GB RAM.
- Known ComfyUI environment: Python 3.13 and PyTorch CUDA 13.
- Primary role: performance, full training, high-resolution testing and DFM export.
- The ComfyUI environment is not a DeepFaceLab baseline and must remain separate.

Each machine can have multiple environment profiles, for example `system-py312`, `system-cu130`, and `legacy-dfl-baseline`. Results from different environment profiles must not be compared as though they were the same runtime.

## In progress

- [ ] Pull and run the PowerShell 5.1 fixes on `hp-a2000`.
- [ ] Create ignored local profiles for both machines.
- [ ] Run profile-labelled diagnostics on both machines.
- [ ] Identify the exact historical runtime bundle or dependency environment for the first baseline.
- [ ] Prepare a small, authorized, non-public test dataset.
- [ ] Execute extraction, short training, save/resume, merge, DFM export, and VisoMaster Fusion loading.

## Next local acceptance work

1. Pull the latest `agent/p0-reproducible-baseline` changes on each machine.
2. Copy `config/machine-profile.example.psd1` into `config/local/` and create one profile for the current system environment on each machine.
3. Run `scripts/windows/run-profiled-p0.ps1` using the matching local profile.
4. Review reports under `artifacts/p0/<machine>/<environment>/`.
5. Locate or install a self-contained historical DeepFaceLab Windows runtime without reusing FaceFusion, VisoMaster, or ComfyUI environments.
6. Create a new `legacy-dfl-baseline` profile for the selected machine and runtime.
7. Prepare a small authorized test dataset outside the repository.
8. Validate extraction, short training, save/resume, merge, DFM export, and VisoMaster Fusion loading.
9. Attach only redacted JSON reports and measured results to the P0 pull request.

## Known risks

- The inherited CUDA requirements pin old packages including NumPy 1.19.3, h5py 2.10.0, OpenCV 4.1.0.25, SciPy 1.4.1, TensorFlow GPU 2.4.0, and tf2onnx 1.9.3.
- Modern Python/CUDA upgrades may break binary compatibility, checkpoint behavior, numerical output, or DFM export.
- RTX A2000 has limited VRAM, so training settings must be conservative on that machine.
- Windows build 26200 is newer than the historical runtime and may expose compatibility issues.
- The RTX 5880's existing Python 3.13/CUDA 13 ComfyUI environment must not be mistaken for a compatible DeepFaceLab environment.
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

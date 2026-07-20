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
- Both computers are equal, complete development nodes with independent local environments.

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
- [x] Create and run `hp-a2000 × system-py312` local profile.
- [x] Pass the P0 environment scaffold on `hp-a2000 × system-py312` at commit `9d6cc7b6494dcd3e0f75b60c395f976159470e60`.
- [x] Correct the multi-machine design: no permanent work split between computers.
- [x] Make `full-development` the default profile label while preserving older labels for compatibility.

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

This result validates the local system profile and scripts only. It is **not** the historical DeepFaceLab end-to-end baseline.

## Two-computer development model

Both computers may perform the same work:

- Source-code and PowerShell development.
- Dependency and compatibility work.
- Extraction and training tests.
- Save/resume, merge, DFM export, and consumer validation.
- Documentation, commits, pull requests, and releases.

Only local state is independent:

- Repository working directory.
- Python/CUDA/FFmpeg/runtime paths.
- `config/local/` profile files.
- `artifacts/`, `workspace/`, datasets, checkpoints, and DFM files.

GitHub synchronizes source code and shared documentation. Local environments and generated data are never synchronized through Git.

Known physical machines:

- `hp-a2000`: current `system-py312` profile passed.
- `rtx5880-ada`: local profile and diagnostic pending until that computer is available.

Neither computer has a permanent engineering, performance, or baseline assignment. Hardware differences are recorded as environment facts only.

## In progress

- [ ] Continue P0 development on whichever computer is currently available.
- [ ] Identify the exact historical runtime bundle or dependency environment for the first baseline.
- [ ] Create `legacy-dfl-baseline` independently on each computer when available.
- [ ] Prepare a small, authorized, non-public test dataset.
- [ ] Execute extraction, short training, save/resume, merge, DFM export, and VisoMaster Fusion loading.
- [ ] Reproduce the accepted baseline on the second computer later without blocking current work.

## Switching computers

Before leaving the current computer:

1. Review `git status` and staged changes.
2. Commit and push all source and shared-document changes.
3. Update `PROGRESS.md` and `NEXT_CHAT_CONTEXT.md` when project state changed.
4. Do not copy the repository with uncommitted changes to the other computer.

On the other computer:

1. `git fetch origin`.
2. Switch to the current feature branch.
3. `git pull --ff-only`.
4. Use that computer's own ignored `config/local/*.psd1` profile.
5. Continue the same development work from the shared commit.

When both computers are used simultaneously, use separate feature branches and merge through pull requests.

## Next local acceptance work

1. Continue on the currently available A2000 computer; the RTX 5880 diagnostic is not a prerequisite.
2. Investigate and document a self-contained historical DeepFaceLab Windows runtime.
3. Keep the historical runtime separate from system Python, FaceFusion, VisoMaster, and ComfyUI.
4. Create an A2000 `legacy-dfl-baseline` local profile when the runtime is known.
5. Validate extraction, short training, checkpoint save/resume, merge, DFM export, and consumer loading.
6. When the RTX 5880 computer becomes available, pull the same source branch and create its own independent profile for the same development workflow.
7. Attach only redacted JSON reports and measured results to the P0 pull request.

## Known risks

- The inherited CUDA requirements pin old packages including NumPy 1.19.3, h5py 2.10.0, OpenCV 4.1.0.25, SciPy 1.4.1, TensorFlow GPU 2.4.0, and tf2onnx 1.9.3.
- Modern Python/CUDA upgrades may break binary compatibility, checkpoint behavior, numerical output, or DFM export.
- Hardware limits may require different test settings, but must not create divergent source behavior.
- The historical TensorFlow/CUDA stack may require different compatibility work on each GPU.
- P0 cannot be accepted from import tests alone; a real save/resume and export workflow is required.

## Milestone status

| Milestone | Status | Exit condition |
|---|---|---|
| P0 Reproducible baseline | Active | End-to-end authorized test run and DFM load verified |
| P1 Engineering reliability | Not started | Installer, diagnostics, tests, logging, recovery |
| P2 Modern GPU compatibility | Not started | Validated modern runtime matrix without regressions |
| P3 Workflow improvements | Not started | Dataset, XSeg, queue, dashboard, export improvements |
| P4 Algorithm research | Not started | Benchmarked optional modern backends/models |

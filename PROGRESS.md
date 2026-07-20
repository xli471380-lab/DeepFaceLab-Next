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
- [x] Pass the P0 environment scaffold on `hp-a2000 × system-py312`.
- [x] Correct the multi-machine design: no permanent work split between computers.
- [x] Add safe computer-switch BAT files.
- [x] Add local historical-runtime discovery tooling.
- [x] Scan all fixed drives on `hp-a2000` and confirm no reusable historical portable bundle is installed.
- [x] Fix CMD UTF-8 parsing in the discovery BAT by using ASCII-only output.
- [x] Obtain the official-linked RTX 3000 Windows package without executing it.
- [x] Record the package filename, byte size, SHA-256, and unsigned Authenticode status.
- [x] Add a one-click static package inspection BAT and PowerShell inspection script.

## Verified local results

### `hp-a2000 × system-py312`

Status: **environment scaffold passed**.

Observed:

- Windows 11 Pro build 26200; PowerShell 5.1.
- Intel Core i5-12500; approximately 16 GB RAM.
- NVIDIA RTX A2000; 5754 MiB VRAM from `nvidia-smi`.
- NVIDIA driver 581.80; compute capability 8.6.
- System Python 3.12.10 probe passed.
- Git and repository integrity checks passed.
- No workspace, artifacts, or DFM files were tracked.
- FFmpeg and `nvcc` were not available on PATH; non-blocking for the system profile.

This validates the local system profile and scripts only. It is not the historical DeepFaceLab end-to-end baseline.

### Historical runtime discovery

Search roots: `C:\`, `D:\`, `E:\`, `F:\`, and `G:\`.

Result:

- Candidate count: 1.
- Likely portable-bundle count: 0.
- The only candidate was `D:\DeepFaceLab-Next`, identified as a source checkout.
- No embedded Python, FFmpeg, `_internal` runtime, or portable workspace was found.

Conclusion: P0 requires a separately obtained historical Windows runtime.

### Downloaded historical package

Local file:

```text
F:\FDeepFaceLab-Historical-Downloads\DeepFaceLab\DeepFaceLab_NVIDIA_RTX3000_series_build_11_20_2021.exe
```

Recorded metadata:

- Size: `3919330734` bytes.
- SHA-256: `4CA31C30CA8F683A825A643E7090811D750C1250775537DCDB5C80D5F3B7F722`.
- Authenticode status: `NotSigned`.
- The file was obtained from an upstream README-linked Windows mirror.
- The upstream README and GitHub release pages do not provide a published checksum or signature for this exact EXE, so the local hash is a fingerprint, not proof of authorship.

## Two-computer development model

Both computers may perform the same work. Only local Python/CUDA/FFmpeg paths, profiles, artifacts, workspaces, datasets, checkpoints, and DFM files remain independent. GitHub synchronizes source code and shared documentation.

## In progress

- [ ] Run the new static package inspection step.
- [ ] Review Microsoft Defender output.
- [ ] Use 7-Zip to list and integrity-test the self-extracting archive without running it.
- [ ] Confirm the archive contains a plausible DeepFaceLab portable structure.
- [ ] Extract into a separate local runtime directory outside the source repository.
- [ ] Create a `legacy-dfl-baseline` local profile for the extracted runtime.
- [ ] Verify embedded Python, TensorFlow, CUDA/cuDNN, FFmpeg, and GPU detection.
- [ ] Prepare a small, authorized, non-public test dataset.
- [ ] Execute extraction, short training, save/resume, merge, DFM export, and VisoMaster Fusion loading.
- [ ] Reproduce the accepted baseline on the second computer later without blocking current work.

## Next local acceptance work

1. Pull the latest branch to receive `4_检查下载包.bat`.
2. Run the static inspection BAT against the downloaded EXE.
3. Do not run the downloaded EXE yet.
4. Review the generated JSON, Defender log, and 7-Zip archive-test output.
5. If 7-Zip is missing, install it from its official source or provide its existing path, then repeat the inspection.
6. Extract the accepted archive to a short separate directory such as `F:\DFL-Legacy` to avoid historical path-length problems.
7. Create an ignored `legacy-dfl-baseline` profile pointing to the embedded tools.
8. Validate the historical environment before using authorized test media.

## Known risks

- The inherited CUDA requirements pin old packages including NumPy 1.19.3, h5py 2.10.0, OpenCV 4.1.0.25, SciPy 1.4.1, TensorFlow GPU 2.4.0, and tf2onnx 1.9.3.
- Modern Python/CUDA upgrades may break binary compatibility, checkpoint behavior, numerical output, or DFM export.
- Historical Windows bundles are externally hosted and must be treated as untrusted until inspected.
- The downloaded EXE is unsigned and has no official published checksum located so far.
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

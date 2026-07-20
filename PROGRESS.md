# DeepFaceLab-Next Progress

Last updated: 2026-07-20

## Project state

- Repository: `xli471380-lab/DeepFaceLab-Next`.
- Frozen upstream baseline on `master`: `e4b7543ffa1d73b26fce1e31852727f658ba490c`.
- Integration branch: `develop`.
- Active branch: `agent/p0-reproducible-baseline`.
- Draft pull request: `#1 P0: establish reproducible baseline framework`.
- Current milestone: **P0 — Reproducible historical baseline**.
- Both computers are equal development nodes with independent local profiles, runtime files, workspaces, datasets, checkpoints, DFM files, and artifacts.

## Completed

- [x] Fork and freeze the archived upstream source.
- [x] Define the staged modernization roadmap, P0 protocol, security policy, and branch workflow.
- [x] Add PowerShell 5.1-compatible diagnostics, profile-driven acceptance, per-profile artifacts, and safe computer-switch BAT files.
- [x] Pass the system-profile scaffold on `hp-a2000 × system-py312`.
- [x] Confirm no reusable historical DeepFaceLab portable bundle was already installed.
- [x] Obtain the upstream-linked RTX 3000 Windows package without executing it.
- [x] Record package size, SHA-256, unsigned status, and 7-Zip SFX metadata.
- [x] Install 7-Zip 26.02 from the verified WinGet package.
- [x] List and integrity-test the downloaded SFX without running it.
- [x] Diagnose Microsoft Defender as inactive because Huorong is the active protection provider.
- [x] Confirm Huorong Security 6.0.11.1 is active through `HipsDaemon`, `HipsTray`, and `HRWSCCtrl`.
- [x] Run Huorong custom scan against the downloaded package folder: `0` risks.
- [x] Run Microsoft Safety Scanner custom scan against the downloaded package folder: `No infection found`, return code `0`.
- [x] Confirm the package SHA-256 remained unchanged after scanning.
- [x] Add guarded extraction tooling that verifies the expected hash, rejects unsafe archive paths, tests integrity, extracts outside the repository, and writes an inventory.
- [x] Fix 7-Zip metadata parsing so the SFX path itself is not misclassified as an archive entry.
- [x] Extract the verified SFX with 7-Zip without executing it.
- [x] Scan the extracted runtime with Huorong: `74941` objects, `0` risks.
- [x] Confirm a plausible DeepFaceLab portable runtime structure with embedded Python, FFmpeg, `_internal`, `main.py`, and `workspace`.
- [x] Create an ignored local historical runtime profile.
- [x] Pass the read-only Python/FFmpeg/NVIDIA/CUDA-DLL probe without running `main.py`.
- [x] Add static BAT/environment inspection that does not execute BAT files, TensorFlow, or DeepFaceLab.
- [x] Fix recursive BAT enumeration so inaccessible historical TensorFlow include-tree paths are recorded and skipped instead of aborting the inspection.
- [x] Pass static BAT/environment inspection: 60 BAT files, 56 top-level BAT files, 1 skipped enumeration path, 0 BAT read/hash errors, and 128 relevant environment lines.
- [x] Add a dedicated legacy Python layout inspection for `._pth`, `sys.path`, `site-packages`, package folders, static version files, and launcher BAT text.
- [x] Confirm `git -c http.version=HTTP/1.1 pull --ff-only` works around the observed GitHub `Empty reply from server` failure.

## Verified local results

### `hp-a2000 × system-py312`

Status: **environment scaffold passed**.

- Windows 11 Pro build 26200; PowerShell 5.1.
- Intel Core i5-12500; approximately 16 GB RAM.
- NVIDIA RTX A2000; 5754 MiB VRAM.
- NVIDIA driver 581.80; compute capability 8.6.
- System Python 3.12.10 probe passed.
- No workspace, artifacts, or DFM files are tracked.

This validates the system profile and repository tooling only; it is not the historical DeepFaceLab baseline.

### Downloaded historical package

```text
F:\FDeepFaceLab-Historical-Downloads\DeepFaceLab\DeepFaceLab_NVIDIA_RTX3000_series_build_11_20_2021.exe
```

- Size: `3919330734` bytes.
- SHA-256: `4CA31C30CA8F683A825A643E7090811D750C1250775537DCDB5C80D5F3B7F722`.
- Authenticode: `NotSigned`.
- SFX stub metadata: 7-Zip 19.00.
- Archive integrity test: exit code `0`.
- Raw 7-Zip `Path =` values: `29099`.
- Real archive entries validated: `29098`.
- Huorong package-folder scan: `0` risks.
- Microsoft Safety Scanner custom scan: `No infection found`, return code `0`.
- The upstream-linked mirrors did not provide a published checksum or signature for this exact EXE. The recorded hash is a stable local fingerprint, not proof of authorship.

### Extracted historical runtime

Extraction destination:

```text
F:\DFL-Legacy\DFL_NVIDIA_RTX3000_20211120
```

Portable runtime root:

```text
F:\DFL-Legacy\DFL_NVIDIA_RTX3000_20211120\DeepFaceLab_NVIDIA_RTX3000_series
```

Extraction result:

- Expected SHA-256 matched: `True`.
- Archive integrity test exit code: `0`.
- Extraction exit code: `0`.
- Extracted files: `23376`.
- Extracted directories: `5722`.
- Extracted size: `8146405202` bytes.
- BAT files: `60`; EXE files: `67`; DLL files: `365`; Python files: `7315`.
- Huorong extracted-runtime scan: `74941` objects, `0` risks, `0` processed.

Confirmed paths:

```text
Python:
F:\DFL-Legacy\DFL_NVIDIA_RTX3000_20211120\DeepFaceLab_NVIDIA_RTX3000_series\_internal\python-3.6.8\python.exe

FFmpeg:
F:\DFL-Legacy\DFL_NVIDIA_RTX3000_20211120\DeepFaceLab_NVIDIA_RTX3000_series\_internal\ffmpeg\ffmpeg.exe

DeepFaceLab main.py:
F:\DFL-Legacy\DFL_NVIDIA_RTX3000_20211120\DeepFaceLab_NVIDIA_RTX3000_series\_internal\DeepFaceLab\main.py

Workspace:
F:\DFL-Legacy\DFL_NVIDIA_RTX3000_20211120\DeepFaceLab_NVIDIA_RTX3000_series\workspace
```

### Read-only runtime probe

- Local ignored profile:
  `config\local\hp-a2000-legacy-dfl-rtx3000-20211120.psd1`.
- Status: `passed`.
- Embedded Python: `3.6.8`, 64-bit.
- FFmpeg: `4.2.1`.
- GPU: `NVIDIA RTX A2000`, driver `581.80`, 5754 MiB, compute capability `8.6`.
- Bundled CUDA/cuDNN records: `8`.
- Observed DLLs include CUDA 10.1/11 runtime components, cuBLAS 11, cuSolver 11, cuSparse 11, and cuDNN 8.
- `main.py` was not executed; training was not started; workspace was not intentionally modified.

### Static environment inspection

- Status: `passed`.
- BAT files read: `60`.
- Top-level BAT files: `56`.
- Skipped enumeration errors: `1`.
- BAT read/hash errors: `0`.
- Relevant environment lines: `128`.
- The skipped path is in a historical TensorFlow/cuDNN frontend include tree and is irrelevant to BAT inspection.
- `pkg_resources` reported only one distribution record and zero selected package records even though TensorFlow package directories are visibly present. Therefore pip/pkg_resources metadata is not authoritative for this portable bundle.
- The likely explanations are stripped distribution metadata or a bundle-specific Python path layout. This must be resolved through filesystem and `sys.path` inspection before TensorFlow import.

## In progress

- [ ] Pull and run `9_诊断历史Python依赖布局.bat`.
- [ ] Record embedded Python `sys.path`, `._pth` files, `site-packages` visibility, package directories, static version files, and launcher environment lines.
- [ ] Build a separate controlled TensorFlow/CUDA/GPU visibility probe using the confirmed bundle path setup.
- [ ] Prepare a small authorized, non-public test dataset.
- [ ] Execute face extraction, short training, save/exit, resume, merge, DFM export, and VisoMaster Fusion loading.
- [ ] Reproduce the accepted baseline on the second computer later without blocking current work.

## Next local acceptance work

1. Pull the latest branch with HTTP/1.1.
2. Run `9_诊断历史Python依赖布局.bat` and type `DIAGNOSE`.
3. Review `legacy-python-layout-inspection-*.json`.
4. Confirm whether `Lib\site-packages` is on default `sys.path`, what `._pth` files contain, and which selected package folders/version files exist.
5. Do not run bundled BAT files, TensorFlow import, or `main.py` yet.
6. Add and run a separate controlled TensorFlow/CUDA/GPU probe after the layout report is accepted.

## Known risks

- The inherited historical stack contains old Python, TensorFlow, CUDA, cuDNN, NumPy, SciPy, h5py, OpenCV, ONNX, and tf2onnx components.
- Modern Python/CUDA upgrades may break binary compatibility, checkpoint behavior, numerical output, or DFM export.
- The downloaded EXE is unsigned and has no located official published checksum.
- Clean local scans reduce risk but do not prove publisher identity or absolute safety.
- Huorong is the active antivirus provider; Defender scan failures are expected while Huorong remains active.
- The portable bundle may have stripped or nonstandard Python package metadata, so pip/pkg_resources output alone cannot establish dependency presence.
- Historical TensorFlow/CUDA compatibility may differ between the RTX A2000 and RTX 5880 Ada systems.
- P0 cannot be accepted from import tests alone; a real save/resume, merge, export, and DFM-load workflow is required.

## Milestone status

| Milestone | Status | Exit condition |
|---|---|---|
| P0 Reproducible baseline | Active | End-to-end authorized test run and DFM load verified |
| P1 Engineering reliability | Not started | Installer, diagnostics, tests, logging, recovery |
| P2 Modern GPU compatibility | Not started | Validated modern runtime matrix without regressions |
| P3 Workflow improvements | Not started | Dataset, XSeg, queue, dashboard, export improvements |
| P4 Algorithm research | Not started | Benchmarked optional modern backends/models |

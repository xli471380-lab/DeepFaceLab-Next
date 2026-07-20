# DeepFaceLab-Next Progress

Last updated: 2026-07-20

## Project state

- Repository: `xli471380-lab/DeepFaceLab-Next`.
- Frozen upstream baseline on `master`: `e4b7543ffa1d73b26fce1e31852727f658ba490c`.
- Integration branch: `develop`.
- Active branch: `agent/p0-reproducible-baseline`.
- Draft pull request: `#1 P0: establish reproducible baseline framework`.
- Current milestone: **P0 — Reproducible historical baseline**.
- Both computers are independent development nodes with local profiles, runtimes, workspaces, media, checkpoints, DFM files, and generated artifacts kept outside Git.

## Completed

- [x] Fork and freeze the archived upstream source.
- [x] Define the staged modernization roadmap, P0 protocol, security policy, and branch workflow.
- [x] Add PowerShell 5.1-compatible diagnostics, profile-driven acceptance, per-profile artifacts, and safe computer-switch BAT files.
- [x] Pass the system-profile scaffold on `hp-a2000 × system-py312`.
- [x] Obtain, fingerprint, scan, integrity-test, and safely extract the upstream-linked RTX 3000 historical Windows package without executing its SFX.
- [x] Confirm the portable runtime structure with embedded Python, FFmpeg, `_internal`, DeepFaceLab `main.py`, and `workspace`.
- [x] Pass the historical runtime read-only probe and static BAT/environment inspection on `hp-a2000` without executing `main.py` or starting training.
- [x] Add dedicated legacy Python layout inspection for `._pth`, `sys.path`, `site-packages`, package folders, static version files, and launcher BAT text.
- [x] Synchronize the RTX 5880 Ada computer and create ignored local profiles for its system and historical runtime environments.
- [x] Complete RTX 5880 Ada system diagnostics with zero warnings.
- [x] Scan fixed drives `C:\`, `D:\`, and `E:\`; find no reusable historical portable bundle.
- [x] Re-download the historical RTX 3000 package and confirm exact size `3919330734` bytes and SHA-256 `4CA31C30CA8F683A825A643E7090811D750C1250775537DCDB5C80D5F3B7F722`.
- [x] Safely extract the verified package without executing its SFX: integrity exit `0`, extraction exit `0`, 29098 archive entries, 23376 files, and 5722 directories.
- [x] Pass the RTX 5880 Ada read-only runtime probe and static BAT/environment inspection.
- [x] Pass legacy Python layout inspection on RTX 5880 Ada: both probes completed without timeout; default `sys.path` includes `site-packages`; 138 top-level items, 65 metadata directories, 9 selected artifact groups, 56 top-level BAT files, 112 relevant launcher lines, and 0 warnings.
- [x] Implement and pass step 10 controlled TensorFlow/CUDA/GPU visibility probing with strict timeout, process-tree termination, sanitized environment, captured logs, sentinel JSON, and workspace comparison.
- [x] Record the user's explicit zero-risk active-antivirus confirmation before step 10.
- [x] Pass step 10 on RTX 5880 Ada: TensorFlow `2.6.0`, CUDA build `True`, physical GPU count `1`, local GPU count `1`, timeout `False`, effective exit code `0`, and workspace unchanged `True`.
- [x] Add `P0_E2E_TEST_PLAN.md` with authorization, privacy, extraction, short-training, save/resume, merge, DFM export, and VisoMaster Fusion acceptance gates.
- [x] Implement step 11 authorized dataset preflight with path isolation, authorization confirmation, file/size limits, SHA-256 inventory, bounded `ffprobe` metadata sampling, identical-file rejection, and repository/workspace checks.
- [x] Pass step 11 using two distinct ControlFace10K synthetic identities: source 3 PNG files / 840910 bytes; destination 3 PNG files / 888285 bytes; identical SHA-256 overlap `0`; repository unchanged; historical default workspace unchanged.
- [x] Implement step 12 isolated P0 workspace preparation with passed-manifest validation, full source-hash revalidation, new-target-only semantics, temporary staging, copied-file hash verification, and no DeepFaceLab or TensorFlow execution.
- [x] Pass step 12 on RTX 5880 Ada: 3 source and 3 destination images copied to `D:\DFL-P0-Authorized\workspace-p0`; historical default workspace unchanged; repository unchanged.
- [x] Implement step 13 controlled face extraction with passed-step-10/12 prerequisites, immutable input verification, isolated historical DLL paths, fixed S3FD whole-face parameters, per-role timeouts, temporary outputs, DFLJPG metadata validation, failure cleanup, and no training.
- [x] Keep step 13 fail closed: existing aligned outputs are never deleted; both roles must pass before temporary outputs are committed; input hashes, historical default workspace, and Git status must remain unchanged.
- [x] Confirm `git -c http.version=HTTP/1.1 pull --ff-only` works around the observed GitHub transport failures without disabling certificate verification.

## Verified local results

### `hp-a2000 × system-py312`

Status: **environment scaffold passed**.

- Windows 11 Pro build 26200; PowerShell 5.1.
- Intel Core i5-12500; approximately 16 GB RAM.
- NVIDIA RTX A2000; 5754 MiB VRAM.
- NVIDIA driver 581.80; compute capability 8.6.
- System Python 3.12.10 probe passed.
- No workspace, artifacts, or DFM files are tracked.

### `rtx5880-ada × system-py311`

Status: **system diagnostics complete with zero warnings**.

- Computer: `DESKTOP-84BCCU9`; ASUS system.
- Windows 11 Home Chinese edition, build 26200; PowerShell 5.1.26100.8875.
- Intel Core i5-12600KF; 10 cores / 16 logical processors.
- Physical memory: approximately 63.8 GB.
- NVIDIA RTX 5880 Ada Generation; 46068 MiB VRAM.
- NVIDIA driver 582.16; compute capability 8.9.
- System Python 3.11.9.
- System FFmpeg: `C:\ffmpeg_latest\bin\ffmpeg.exe`.
- System `nvcc`: CUDA 13.1.
- System CUDA/cuDNN components remain isolated from the historical P0 runtime.

### `rtx5880-ada × legacy-dfl-rtx3000-20211120`

Status: **historical runtime, Python layout, TensorFlow/GPU visibility, dataset preflight, and isolated workspace preparation passed**.

Runtime root:

```text
D:\DFL-Legacy\DFL_NVIDIA_RTX3000_20211120\DeepFaceLab_NVIDIA_RTX3000_series
```

Observed:

- Historical package fingerprint matched exactly.
- Embedded Python: `3.6.8`.
- Read-only runtime probe: `passed`.
- Static environment inspection: `passed`.
- Python layout inspection schema v4: `passed`.
- TensorFlow/GPU visibility: `passed`; TensorFlow `2.6.0`; CUDA build `True`; one physical and one local GPU.
- Step 10 report: `artifacts\p0\rtx5880-ada\legacy-dfl-rtx3000-20211120\tensorflow-gpu-probe\legacy-tensorflow-gpu-visibility-20260720T125554Z.json`.
- Step 11 manifest: `artifacts\p0\rtx5880-ada\legacy-dfl-rtx3000-20211120\dataset-preflight\p0-authorized-dataset-manifest-20260720T132514Z.json`.
- Isolated workspace: `D:\DFL-P0-Authorized\workspace-p0`.
- Step 12 report: `artifacts\p0\rtx5880-ada\legacy-dfl-rtx3000-20211120\workspace-preparation\p0-isolated-workspace-preparation-20260720T133322Z.json`.
- Source inputs: `src_0001.png` through `src_0003.png`.
- Destination inputs: `dst_0001.png` through `dst_0003.png`.
- Source and destination `aligned` directories are empty before step 13.
- Historical default workspace and Git repository remained unchanged through step 12.
- Face extraction, model creation, training, merge, and DFM export have not yet been executed.

## Historical package baseline verified on `hp-a2000`

Original package:

```text
F:\FDeepFaceLab-Historical-Downloads\DeepFaceLab\DeepFaceLab_NVIDIA_RTX3000_series_build_11_20_2021.exe
```

- Size: `3919330734` bytes.
- SHA-256: `4CA31C30CA8F683A825A643E7090811D750C1250775537DCDB5C80D5F3B7F722`.
- Authenticode: `NotSigned`.
- SFX stub metadata: 7-Zip 19.00.
- Archive integrity exit code: `0`.
- Huorong package-folder scan: `0` risks.
- Microsoft Safety Scanner: `No infection found`, return code `0`.
- The fingerprint is a stable local identity check, not proof of publisher identity.

## In progress

- [ ] Complete step 9 on `hp-a2000` when that computer is used again.
- [ ] Run step 13 on RTX 5880 Ada and review source/destination extraction logs plus DFLJPG metadata validation.
- [ ] Visually review the six aligned synthetic faces after step 13 passes.
- [ ] Design and run a separately bounded short-training stage with save/exit and resume gates.
- [ ] Execute merge, DFM export, and VisoMaster Fusion loading under the staged acceptance plan.

## Next local work on RTX 5880 Ada

1. Pull the step-13 implementation and this progress update.
2. Run PowerShell 5.1 syntax validation and Python 3.6 compilation validation for the new scripts.
3. Run `13_受控提取P0人脸.bat` against `D:\DFL-P0-Authorized\workspace-p0`.
4. Review only the terminal summary and report/log paths; do not upload the actual face images.
5. Do not start training until both aligned roles and DFLJPG metadata validation pass.

## Known risks

- The historical stack contains old Python, TensorFlow, CUDA, cuDNN, NumPy, SciPy, h5py, OpenCV, ONNX, and tf2onnx components.
- Modern dependency upgrades may break binary compatibility, checkpoint behavior, numerical output, or DFM export.
- The downloaded EXE is unsigned and no official published checksum was located.
- Clean local scans reduce risk but do not prove publisher identity or absolute safety.
- TensorFlow/GPU visibility has passed, but extraction, training, checkpoint save/resume, merge, export, and DFM loading remain distinct acceptance gates.
- Three images per identity are suitable for pipeline validation only, not quality evaluation.
- S3FD/FAN extraction may still fail or hang independently of TensorFlow device visibility; step 13 therefore remains isolated and time-limited.
- P0 cannot be accepted until save/resume, merge, DFM export, and VisoMaster Fusion loading are verified.

## Milestone status

| Milestone | Status | Exit condition |
|---|---|---|
| P0 Reproducible baseline | Active | End-to-end authorized test run and DFM load verified |
| P1 Engineering reliability | Not started | Installer, diagnostics, tests, logging, recovery |
| P2 Modern GPU compatibility | Not started | Validated modern runtime matrix without regressions |
| P3 Workflow improvements | Not started | Dataset, XSeg, queue, dashboard, export improvements |
| P4 Algorithm research | Not started | Benchmarked optional modern backends/models |

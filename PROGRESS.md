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
- [x] Obtain, fingerprint, scan, integrity-test, and safely extract the upstream-linked RTX 3000 historical Windows package without executing its SFX.
- [x] Confirm a plausible portable runtime structure with embedded Python, FFmpeg, `_internal`, DeepFaceLab `main.py`, and `workspace`.
- [x] Pass the historical runtime read-only probe on `hp-a2000` without executing `main.py` or starting training.
- [x] Pass static BAT/environment inspection on `hp-a2000`: 60 BAT files, 56 top-level BAT files, 1 skipped include-tree path, 0 read/hash errors, and 128 relevant environment lines.
- [x] Add dedicated legacy Python layout inspection for `._pth`, `sys.path`, `site-packages`, package folders, static version files, and launcher BAT text.
- [x] Synchronize the second computer to `agent/p0-reproducible-baseline` and create the ignored `rtx5880-ada × system-py311` profile.
- [x] Complete second-computer system diagnostics with zero warnings.
- [x] Scan fixed drives `C:\`, `D:\`, and `E:\` on the RTX 5880 Ada computer; find 2 candidates but 0 reusable historical portable bundles.
- [x] Fix discovery input so blank input or `ALL` selects all fixed drives, while explicit roots are parsed without CMD/PowerShell pipe escaping errors.
- [x] Parameterize steps 6–9 so package paths, extraction destinations, machine IDs, environment IDs, and local profile paths can differ between computers.
- [x] Re-download the historical RTX 3000 package on the RTX 5880 Ada computer and confirm exact size `3919330734` bytes and SHA-256 `4CA31C30CA8F683A825A643E7090811D750C1250775537DCDB5C80D5F3B7F722`.
- [x] Safely extract the verified package on the RTX 5880 Ada computer without executing the SFX: integrity exit `0`, extraction exit `0`, 29098 archive entries, 23376 files, and 5722 directories.
- [x] Create the ignored `rtx5880-ada-legacy-dfl-rtx3000-20211120.psd1` profile and pass the read-only runtime probe.
- [x] Confirm the RTX 5880 Ada historical profile uses embedded Python 3.6.8, bundled FFmpeg successfully, and 8 bundled CUDA/cuDNN DLL records; `main.py` was not executed.
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

### `rtx5880-ada × system-py311`

Status: **system diagnostics complete with zero warnings**.

- Computer: `DESKTOP-84BCCU9`; ASUS system.
- Windows 11 Home Chinese edition, build 26200; PowerShell 5.1.26100.8875.
- Intel Core i5-12600KF; 10 cores / 16 logical processors.
- Physical memory: approximately 63.8 GB.
- NVIDIA RTX 5880 Ada Generation; 46068 MiB VRAM.
- NVIDIA driver 582.16; compute capability 8.9.
- System Python profile: Python 3.11.9 at `C:\Users\newAda\AppData\Local\Programs\Python\Python311\python.exe`.
- Python launcher also sees Python 3.10, 3.12, and 3.13.
- System FFmpeg is available at `C:\ffmpeg_latest\bin\ffmpeg.exe`.
- System `nvcc` is CUDA 13.1 at `C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v13.1\bin\nvcc.exe`.
- Environment variables also reference CUDA 13.0/13.3 and cuDNN for CUDA 12.9. These modern system components must not be substituted for the self-contained historical P0 runtime.
- Repository branch and commit were correct and the working tree was clean.
- Fixed-drive runtime discovery searched `C:\`, `D:\`, and `E:\`; candidates: 2; likely portable bundles: 0.

This system profile validates hardware and tooling only. Python 3.11, modern FFmpeg, CUDA 13.x, and system cuDNN are not the historical DeepFaceLab runtime.

### `rtx5880-ada × legacy-dfl-rtx3000-20211120`

Status: **historical runtime extracted and read-only probe passed**.

Package:

```text
D:\DFL-Historical-Downloads\DeepFaceLab\DeepFaceLab\DeepFaceLab_NVIDIA_RTX3000_series_build_11_20_2021.exe
```

Runtime root:

```text
D:\DFL-Legacy\DFL_NVIDIA_RTX3000_20211120\DeepFaceLab_NVIDIA_RTX3000_series
```

Observed:

- Package size: `3919330734` bytes.
- SHA-256 matched the historical baseline exactly.
- Archive integrity test exit code: `0`.
- Extraction exit code: `0`.
- Archive entries checked: `29098`.
- Extracted files: `23376`; directories: `5722`.
- Embedded Python candidates: `1`; FFmpeg candidates: `1`.
- Local ignored profile created: `config\local\rtx5880-ada-legacy-dfl-rtx3000-20211120.psd1`.
- Read-only probe status: `passed`.
- Embedded Python: `3.6.8`.
- Bundled FFmpeg exit code: `0`.
- Selected package metadata records: `0`; this is consistent with the portable bundle's incomplete package metadata and is not yet treated as a missing-dependency verdict.
- Bundled CUDA/cuDNN DLL records: `8`.
- DeepFaceLab `main.py` was not executed and training was not started.

The active-antivirus scan result for the extracted directory has not yet been recorded in the project progress and must not be assumed.

## Historical package baseline verified on `hp-a2000`

Original package:

```text
F:\FDeepFaceLab-Historical-Downloads\DeepFaceLab\DeepFaceLab_NVIDIA_RTX3000_series_build_11_20_2021.exe
```

- Size: `3919330734` bytes.
- SHA-256: `4CA31C30CA8F683A825A643E7090811D750C1250775537DCDB5C80D5F3B7F722`.
- Authenticode: `NotSigned`.
- SFX stub metadata: 7-Zip 19.00.
- Archive integrity test exit code: `0`.
- Real archive entries validated: `29098`.
- Huorong package-folder scan: `0` risks.
- Microsoft Safety Scanner custom scan: `No infection found`, return code `0`.
- The hash is a stable local fingerprint, not proof of publisher identity.

## In progress

- [ ] Record the active-antivirus scan result for `D:\DFL-Legacy\DFL_NVIDIA_RTX3000_20211120` on the RTX 5880 Ada computer.
- [ ] Run parameterized step 8 against `rtx5880-ada-legacy-dfl-rtx3000-20211120.psd1`.
- [ ] Run parameterized step 9 against the same historical profile.
- [ ] Complete step 9 on `hp-a2000` when that computer is used again.
- [ ] Build a controlled TensorFlow/CUDA/GPU visibility probe from the confirmed bundle path setup.
- [ ] Prepare a small authorized, non-public test dataset.
- [ ] Execute face extraction, short training, save/exit, resume, merge, DFM export, and VisoMaster Fusion loading.

## Next local work on RTX 5880 Ada

1. Confirm and record the active-antivirus scan result for the extracted directory.
2. Run parameterized step 8 using the RTX 5880 Ada historical profile.
3. Review the static BAT/environment inspection report.
4. Run parameterized step 9 only after step 8 passes.
5. Do not run TensorFlow imports, bundled launcher BAT files, DeepFaceLab `main.py`, or training yet.

## Known risks

- The historical stack contains old Python, TensorFlow, CUDA, cuDNN, NumPy, SciPy, h5py, OpenCV, ONNX, and tf2onnx components.
- Modern Python/CUDA upgrades may break binary compatibility, checkpoint behavior, numerical output, or DFM export.
- The downloaded EXE is unsigned and no official published checksum was located.
- Clean local scans reduce risk but do not prove publisher identity or absolute safety.
- The portable bundle may have stripped or nonstandard Python package metadata, so pip/pkg_resources output alone cannot establish dependency presence.
- Compatibility may differ between RTX A2000 compute capability 8.6 and RTX 5880 Ada compute capability 8.9.
- System CUDA 13.x and cuDNN 9.x on the second computer must remain isolated from the historical portable runtime.
- P0 cannot be accepted from import tests alone; a real save/resume, merge, export, and DFM-load workflow is required.

## Milestone status

| Milestone | Status | Exit condition |
|---|---|---|
| P0 Reproducible baseline | Active | End-to-end authorized test run and DFM load verified |
| P1 Engineering reliability | Not started | Installer, diagnostics, tests, logging, recovery |
| P2 Modern GPU compatibility | Not started | Validated modern runtime matrix without regressions |
| P3 Workflow improvements | Not started | Dataset, XSeg, queue, dashboard, export improvements |
| P4 Algorithm research | Not started | Benchmarked optional modern backends/models |

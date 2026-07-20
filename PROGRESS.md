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

Extracted runtime on `hp-a2000`:

```text
F:\DFL-Legacy\DFL_NVIDIA_RTX3000_20211120\DeepFaceLab_NVIDIA_RTX3000_series
```

- Extracted files: `23376`.
- Extracted directories: `5722`.
- Extracted size: `8146405202` bytes.
- Huorong extracted-runtime scan: `74941` objects, `0` risks.
- Embedded Python: 3.6.8, 64-bit.
- Bundled FFmpeg: 4.2.1.
- Bundled CUDA/cuDNN DLL records: 8.
- RTX A2000 was visible to `nvidia-smi`; TensorFlow/GPU import is not yet accepted.

## Cross-computer transfer decision

The RTX 5880 Ada computer has no reusable historical bundle. The preferred transfer artifact is the already fingerprinted original 3.9 GB package rather than the 8.1 GB extracted directory because it is smaller and can be independently re-hashed, scanned, integrity-tested, and safely extracted on the second computer.

Do not copy the `hp-a2000` local profile. The RTX 5880 Ada computer must create its own local historical-runtime profile after extraction.

## In progress

- [ ] Transfer the verified historical package to the RTX 5880 Ada computer through a trusted local medium or private network path.
- [ ] Recalculate SHA-256 on the destination and require an exact match before extraction.
- [ ] Scan the transferred package with the active antivirus on the RTX 5880 Ada computer.
- [ ] Install or verify 7-Zip locally, then use parameterized step 6 to extract outside the repository.
- [ ] Scan the extracted directory before executing any included file.
- [ ] Use parameterized step 7 to create `rtx5880-ada-legacy-dfl-rtx3000-20211120.psd1` and run the read-only probe.
- [ ] Run parameterized steps 8 and 9 against the RTX 5880 Ada historical profile.
- [ ] Complete step 9 on `hp-a2000` when that computer is used again.
- [ ] Build a controlled TensorFlow/CUDA/GPU visibility probe from the confirmed bundle path setup.
- [ ] Prepare a small authorized, non-public test dataset.
- [ ] Execute face extraction, short training, save/exit, resume, merge, DFM export, and VisoMaster Fusion loading.

## Next local work on RTX 5880 Ada

1. Pull the latest branch containing parameterized cross-computer BAT files.
2. Confirm at least 15 GB free on the chosen destination drive.
3. Copy only the verified original package from the first computer.
4. Verify the destination SHA-256 exactly matches the recorded fingerprint.
5. Scan the copied package folder with the active antivirus.
6. Run parameterized step 6 with explicit local package and destination paths.
7. Do not run extracted BAT, EXE, Python, or `main.py` until the extracted directory has also been scanned.

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

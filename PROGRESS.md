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
- [x] Fix PowerShell 5.1 empty-result, collection binder, native stderr, Python probe, and signed-HResult formatting issues.
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
- [x] Add one-click static package inspection and Defender diagnostic tools.
- [x] Install 7-Zip 26.02 from the verified WinGet package.
- [x] List and integrity-test the downloaded 7-Zip SFX archive without executing it.
- [x] Confirm the 7-Zip integrity test returns exit code `0` with `29099` listed entries.
- [x] Diagnose Microsoft Defender as `Not running`, with antivirus and real-time protection disabled.
- [x] Confirm Defender scan failures are service-state failures, not malware detections.
- [x] Run Microsoft Safety Scanner quick scan; it removed `VirTool:Win32/DefenderTamperingRestore` from the `DisableAntiSpyware` registry value.
- [x] Confirm Huorong Security 6.0.11.1 is installed and active through `HipsDaemon`, `HipsTray`, and `HRWSCCtrl`.
- [x] Confirm Microsoft Defender is inactive because Huorong is the active real-time protection product; do not force both engines to run concurrently.
- [x] Confirm `git -c http.version=HTTP/1.1 pull --ff-only` works around the observed GitHub `Empty reply from server` failure.

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
- File version metadata identifies a `7-Zip 19.00` SFX stub.
- The file was obtained from an upstream README-linked Windows mirror.
- The upstream README and GitHub release pages do not provide a published checksum or signature for this exact EXE, so the local hash is a fingerprint, not proof of authorship.

Static archive inspection:

- 7-Zip executable: `C:\Program Files\7-Zip\7z.exe`.
- 7-Zip version: `26.02`.
- Archive test exit code: `0`.
- Listed entries: `29099`.
- No archive-corruption error was reported.

Defender diagnostics:

- Administrator: `True`.
- `AMRunningMode`: `Not running`.
- `AntivirusEnabled`: `False`.
- `RealTimeProtectionEnabled`: `False`.
- `Start-MpScan` failed with `0x80131500`.
- `MpCmdRun -ReturnHR` failed with `0x80004005`.
- Matching Defender detections: `0`.
- Conclusion: Microsoft Defender is not the active antivirus provider on this machine, so these failures are not valid clean or malicious verdicts.

Active protection provider:

- Product: `火绒安全软件` / Huorong Security.
- Version: `6.0.11.1`.
- Publisher: `北京火绒网络科技有限公司`.
- `HipsDaemon`: `Running`, `Auto`.
- `HipsTray`: running.
- `HRWSCCtrl`: `Running`; this is Huorong's Windows Security Center integration service.
- Conclusion: Huorong is the active real-time protection product. Microsoft Defender should not be force-started while Huorong remains installed and active.

Microsoft Safety Scanner quick scan:

- Scanner: Microsoft Safety Scanner v1.455, build `1.455.230.0`.
- Detection: `VirTool:Win32/DefenderTamperingRestore`.
- Resource: `HKLM\SOFTWARE\Microsoft\Windows Defender\DisableAntiSpyware`.
- Action: removed successfully (`0x00000000`).
- This quick scan repaired a Defender-related registry setting; it did not scan or validate the downloaded DeepFaceLab package.

## Two-computer development model

Both computers may perform the same work. Only local Python/CUDA/FFmpeg paths, profiles, artifacts, workspaces, datasets, checkpoints, and DFM files remain independent. GitHub synchronizes source code and shared documentation.

## In progress

- [ ] Update Huorong virus definitions and scan the downloaded EXE or its containing folder.
- [ ] Run Microsoft Safety Scanner again in custom-scan mode against the downloaded package folder.
- [ ] Review both scan results and retain screenshots or logs locally.
- [ ] Review the 7-Zip listing for a plausible DeepFaceLab portable structure before extraction.
- [ ] Extract with 7-Zip into a separate local runtime directory without executing the original SFX.
- [ ] Scan the extracted directory with Huorong before running any BAT, EXE, Python, or DLL.
- [ ] Create a `legacy-dfl-baseline` local profile for the extracted runtime.
- [ ] Verify embedded Python, TensorFlow, CUDA/cuDNN, FFmpeg, and GPU detection.
- [ ] Prepare a small, authorized, non-public test dataset.
- [ ] Execute extraction, short training, save/resume, merge, DFM export, and VisoMaster Fusion loading.
- [ ] Reproduce the accepted baseline on the second computer later without blocking current work.

## Next local acceptance work

1. Open Huorong Security and update its virus definitions.
2. Use Huorong custom scan or the Explorer context-menu scan on `F:\FDeepFaceLab-Historical-Downloads\DeepFaceLab`.
3. Run `D:\SecurityTools\msert.exe` again and choose a custom scan for the same folder; the previous run was only a quick scan.
4. Keep the downloaded EXE unexecuted until both scans complete without a package-related detection.
5. Review the saved 7-Zip entry listing and confirm expected portable-runtime markers.
6. Extract with `7z.exe x` into a short separate directory such as `F:\DFL-Legacy`.
7. Scan the extracted directory with Huorong before executing any included files.
8. Create an ignored `legacy-dfl-baseline` profile pointing to the embedded tools.
9. Validate the historical environment before using authorized test media.

## Known risks

- The inherited CUDA requirements pin old packages including NumPy 1.19.3, h5py 2.10.0, OpenCV 4.1.0.25, SciPy 1.4.1, TensorFlow GPU 2.4.0, and tf2onnx 1.9.3.
- Modern Python/CUDA upgrades may break binary compatibility, checkpoint behavior, numerical output, or DFM export.
- Historical Windows bundles are externally hosted and must be treated as untrusted until inspected.
- The downloaded EXE is unsigned and has no official published checksum located so far.
- Huorong is the active antivirus provider; Defender scan failures are expected while Huorong remains active.
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

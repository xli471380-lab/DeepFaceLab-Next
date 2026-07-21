# DeepFaceLab-Next Progress

Last updated: 2026-07-21

## Project state

- Repository: `xli471380-lab/DeepFaceLab-Next`.
- Frozen upstream baseline on `master`: `e4b7543ffa1d73b26fce1e31852727f658ba490c`.
- Integration branch: `develop`.
- Current branch: `agent/p0-reproducible-baseline`.
- Pull request: `#1 P0: establish reproducible baseline framework`.
- P0 status: **accepted and complete on one documented local profile**.
- Current transition: review/merge PR #1, then begin **P1 — Engineering reliability**.
- Local profiles, historical runtimes, workspaces, media, checkpoints, DFM files, and generated artifacts remain outside Git.

## P0 acceptance decision

P0 is accepted on:

```text
rtx5880-ada × legacy-dfl-rtx3000-20211120
```

Accepted end-to-end path:

```text
environment and GPU probe
→ authorized synthetic dataset preflight
→ isolated workspace preparation
→ source/destination face extraction
→ bounded SAEHD training to iteration 2
→ save/exit
→ resume from iteration 2 to iteration 4
→ merge 3 destination images and 3 masks
→ visual review
→ DFM export and ONNX validation
→ VisoMaster Fusion listing, loading, face detection, and one DFM inference
```

The four-iteration model is a pipeline compatibility and reproducibility fixture only. No image-quality claim is made.

## Completed

### Repository and safety framework

- [x] Fork and freeze the archived upstream source.
- [x] Define the staged modernization roadmap, branch model, security policy, responsible-use boundary, and P0 protocol.
- [x] Keep private media, aligned faces, checkpoints, DFM files, embeddings, and local artifacts outside Git.
- [x] Add PowerShell 5.1-compatible diagnostics, profile-driven acceptance, per-profile artifact paths, and safe computer-switch helpers.

### Historical runtime and environment

- [x] Fingerprint, scan, integrity-test, and safely extract the upstream-linked RTX 3000 historical Windows package without executing its SFX.
- [x] Verify package size `3919330734` bytes and SHA-256 `4CA31C30CA8F683A825A643E7090811D750C1250775537DCDB5C80D5F3B7F722`.
- [x] Verify embedded Python `3.6.8`, DeepFaceLab `main.py`, FFmpeg, `_internal`, historical workspace, Python layout, package metadata, and relevant launcher BAT files.
- [x] Pass the controlled TensorFlow/CUDA/GPU visibility probe on RTX 5880 Ada: TensorFlow `2.6.0`, CUDA build `True`, one physical GPU, one local GPU, and unchanged historical workspace.

### Authorized P0 data and extraction

- [x] Use two distinct licensed synthetic ControlFace10K identities: 3 source PNG files and 3 destination PNG files.
- [x] Pass dataset isolation, authorization confirmation, file-count/size limits, SHA-256 inventory, metadata sampling, identical-file rejection, repository checks, and historical-workspace checks.
- [x] Prepare isolated workspace `D:\DFL-P0-Authorized\workspace-p0` through a temporary verified staging boundary.
- [x] Extract 3 valid source and 3 valid destination `whole_face` DFLJPG files using S3FD and GPU index 0.
- [x] Manually review all six aligned outputs with no blank image, inversion, severe crop, or obvious misdetection.

### Training, resume, merge, and export

- [x] Select SAEHD because the historical implementation contains the required DFM export path.
- [x] Pass step 14: create `p0gate_SAEHD` at exact iteration `2`, loss-history count `2`, and 8 committed checkpoint files.
- [x] Pass step 15: resume the same checkpoint from iteration `2` to `4`, preserve the first two loss rows, preserve options except target iteration, change 5 weight/optimizer files, and atomically commit 8 checkpoint files.
- [x] Pass step 16: merge exactly 3 destination images and generate exactly 3 nonzero masks; checkpoint and inputs remain unchanged.
- [x] Complete visual review of the merged images and masks.
- [x] Pass step 17: export one validated DFM from a temporary checkpoint clone using the historical CPU-only export path.
- [x] Validate ONNX checker success, opset `12`, input `in_face`, and outputs `out_face_mask`, `out_celeb_face`, and `out_celeb_face_mask`.

### VisoMaster Fusion compatibility

- [x] Install VisoMaster Fusion in a new isolated portable folder, without reusing FaceFusion, old VisoMaster, ComfyUI, system Python, or DeepFaceLab environments.
- [x] Verify VisoMaster Fusion branch `main`, commit `560c7645d63c07526fe7109fce6abcabf95768fa`.
- [x] Copy and re-hash the DFM under `model_assets\dfm_models`.
- [x] Select `DeepFaceLive (DFM)` and `p0gate_SAEHD_model.dfm`.
- [x] Load one authorized synthetic destination image, detect one target face, execute `Swap Faces`, observe a changed preview, and keep the application responsive.
- [x] Observe no blocking CUDA, TensorRT, provider, tensor-name, or tensor-shape failure during the accepted DFM inference.
- [x] Record P0 Gate F through step 18 with a machine-readable local report and workspace marker.

## Accepted local evidence

### Machine and runtime

- Machine: `DESKTOP-84BCCU9` / `rtx5880-ada`.
- Windows 11 Home Chinese edition, build 26200; PowerShell 5.1.
- Intel Core i5-12600KF; approximately 63.8 GB RAM.
- NVIDIA RTX 5880 Ada Generation; 46068 MiB VRAM.
- NVIDIA driver `582.16`; compute capability `8.9`.
- Historical runtime root: `D:\DFL-Legacy\DFL_NVIDIA_RTX3000_20211120\DeepFaceLab_NVIDIA_RTX3000_series`.
- Historical embedded Python: `3.6.8`.
- Historical TensorFlow: `2.6.0`.

### Final model and DFM

- Model prefix: `p0gate_SAEHD`.
- Final P0 iteration: `4`.
- Checkpoint files: `8`.
- DFM path: `D:\DFL-P0-Authorized\workspace-p0\dfm\p0gate_SAEHD_model.dfm`.
- DFM size: `27654198` bytes.
- DFM SHA-256: `E2F7E8810384FCE392DA0FA8D036795A93282C223E743855E5BCCB1EF22047C8`.
- VisoMaster Fusion commit: `560c7645d63c07526fe7109fce6abcabf95768fa`.

### Final reports

- Resume report: `artifacts\p0\rtx5880-ada\legacy-dfl-rtx3000-20211120\resume-training-save\p0-resume-training-save-v2-20260721T141856Z.json`.
- Merge report: `artifacts\p0\rtx5880-ada\legacy-dfl-rtx3000-20211120\merge\p0-controlled-merge-20260721T142130Z.json`.
- DFM export report: `artifacts\p0\rtx5880-ada\legacy-dfl-rtx3000-20211120\dfm-export\p0-controlled-dfm-export-20260721T142402Z.json`.
- VisoMaster report: `artifacts\p0\rtx5880-ada\legacy-dfl-rtx3000-20211120\visomaster-fusion\p0-visomaster-fusion-acceptance-v2-20260721T150505Z.json`.
- Workspace Gate F marker: `D:\DFL-P0-Authorized\workspace-p0\p0-visomaster-fusion-manifest.json`.

## Other verified node

### `hp-a2000`

- Windows 11 Pro build 26200, Intel Core i5-12500, approximately 16 GB RAM.
- NVIDIA RTX A2000, approximately 6 GB VRAM, driver `581.80`, compute capability `8.6`.
- Historical package fingerprint and runtime layout verified.
- TensorFlow/GPU visibility passed with TensorFlow `2.6.0`.
- A separate P0 run reached extraction, short training, resume, merge, and DFM export, but the project needs only one documented complete profile for P0 acceptance.
- The incomplete isolated VisoMaster portable installation on this computer is not reused or copied.

## Current work

- [ ] Review final PR #1 changes and merge the accepted P0 framework into `develop`.
- [ ] Create `agent/p1-engineering-reliability` from the merged `develop` branch.
- [ ] Implement the first P1 slice: CPU-only repository/report validation and a one-command acceptance summary that never touches media, checkpoints, DFM files, or the historical runtime.
- [ ] Add no-GPU tests for report schemas, path isolation, privacy boundaries, failure classifications, and PowerShell/Python helper logic.

## P1 initial implementation order

1. P1 repository hygiene and privacy validator.
2. P1 report-schema validator for P0 steps 10–18.
3. One-command Windows acceptance-summary orchestrator.
4. Structured failure codes and actionable remediation text.
5. Checkpoint inventory, backup, interruption, rollback, and corruption-recovery design.
6. CPU-only CI workflow.
7. Contributor, release, security, troubleshooting, and rollback documentation.

## Known risks

- The historical runtime contains old Python, TensorFlow, CUDA, cuDNN, NumPy, SciPy, h5py, OpenCV, ONNX, and tf2onnx components.
- Modern dependency upgrades can break binary compatibility, checkpoint behavior, numerical output, merger behavior, or DFM export.
- The historical package is unsigned; exact local fingerprints and clean scans reduce risk but do not prove publisher identity or absolute safety.
- Three images per identity and four total iterations validate the pipeline only, not production quality.
- The VisoMaster preview from the four-iteration model is expected to be poor and must not be presented as a quality benchmark.
- GitHub TLS transport can intermittently fail under Windows Schannel; use a verified retry or per-command OpenSSL backend without disabling certificate verification.

## Milestone status

| Milestone | Status | Exit condition |
|---|---|---|
| P0 Reproducible baseline | **Complete** | Authorized end-to-end run, save/resume, merge, DFM export, and VisoMaster inference recorded |
| P1 Engineering reliability | **Starting** | One-command workflow, structured logs, recovery, no-GPU tests/CI, and engineering documentation |
| P2 Modern GPU compatibility | Not started | Validated modern runtime matrix without P0 regressions |
| P3 Workflow improvements | Not started | Dataset, mask, training, queue, and export workflow improvements |
| P4 Optional algorithm research | Not started | Optional algorithms benchmarked against the frozen P0 baseline |

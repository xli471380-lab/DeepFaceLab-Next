# DeepFaceLab-Next Progress

Last updated: 2026-07-19

## Project state

- Repository fork created: `xli471380-lab/DeepFaceLab-Next`.
- Upstream baseline preserved on `master`.
- Baseline commit: `e4b7543ffa1d73b26fce1e31852727f658ba490c`.
- Integration branch created: `develop`.
- Active branch created: `agent/p0-reproducible-baseline`.
- Current milestone: **P0 — Reproducible historical baseline**.

## Completed

- [x] Fork archived upstream repository.
- [x] Confirm repository ownership and push permissions.
- [x] Define branch strategy.
- [x] Define staged modernization roadmap.
- [x] Freeze the upstream source baseline.
- [x] Add initial development plan.

## In progress

- [ ] Add P0 baseline protocol.
- [ ] Add Windows system-diagnostics script.
- [ ] Add initial P0 acceptance scaffold.
- [ ] Add security and responsible-use policy.
- [ ] Open the first pull request into `develop`.

## Next local acceptance work

1. Clone the fork to a new local directory.
2. Run system diagnostics on the target Windows/NVIDIA workstation.
3. Identify the exact historical runtime bundle or dependency environment used for the first baseline.
4. Prepare a small, authorized, non-public test dataset.
5. Validate extraction, short training, save/resume, merge, DFM export, and VisoMaster Fusion loading.
6. Attach redacted JSON reports and measured results to the P0 pull request.

## Known risks

- The inherited CUDA requirements pin old packages including NumPy 1.19.3, h5py 2.10.0, OpenCV 4.1.0.25, SciPy 1.4.1, TensorFlow GPU 2.4.0, and tf2onnx 1.9.3.
- Modern Python/CUDA upgrades may break binary compatibility, checkpoint behavior, numerical output, or DFM export.
- The repository contains large historical assets and may take substantial time and disk space to clone.
- P0 cannot be accepted from import tests alone; a real save/resume and export workflow is required.

## Milestone status

| Milestone | Status | Exit condition |
|---|---|---|
| P0 Reproducible baseline | Active | End-to-end authorized test run and DFM load verified |
| P1 Engineering reliability | Not started | Installer, diagnostics, tests, logging, recovery |
| P2 Modern GPU compatibility | Not started | Validated modern runtime matrix without regressions |
| P3 Workflow improvements | Not started | Dataset, XSeg, queue, dashboard, export improvements |
| P4 Algorithm research | Not started | Benchmarked optional modern backends/models |

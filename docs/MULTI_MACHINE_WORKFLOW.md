# Multi-machine development workflow

DeepFaceLab-Next treats hardware and runtime as separate dimensions:

```text
machine profile × environment profile = one acceptance result
```

Do not describe a result as belonging only to a computer. The same computer can have a system Python environment, a historical DeepFaceLab bundle, and a future modernized runtime with different compatibility and performance.

## Known maintainer machines

### `hp-a2000`

- Windows 11 Pro, PowerShell 5.1
- Intel Core i5-12500
- About 16 GB RAM
- NVIDIA RTX A2000, about 6 GB VRAM reported by `nvidia-smi`
- Current system environment: Python 3.12; FFmpeg, nvcc, CUDA and cuDNN are not exposed on PATH

Primary role: `engineering`.

Use it for PowerShell 5.1 compatibility, repository work, diagnostics, CPU tests, low-VRAM behavior, extraction tests, and a minimal training smoke test. Its system Python 3.12 environment is not the historical DeepFaceLab baseline.

### `rtx5880-ada`

- NVIDIA RTX 5880 Ada Generation
- About 46 GB VRAM
- About 64 GB RAM
- A known ComfyUI environment uses Python 3.13 and PyTorch with CUDA 13

Primary role: `performance`.

Use it for full training, high-resolution experiments, performance measurements, DFM export, and long-running GPU acceptance. The existing ComfyUI Python/CUDA environment must not be reused as the DeepFaceLab baseline; create a separate environment profile for the historical runtime.

## Profile naming

Use stable, non-personal labels:

```text
MachineId: hp-a2000
EnvironmentId: system-py312
Role: engineering
```

```text
MachineId: rtx5880-ada
EnvironmentId: system-cu130
Role: performance
```

Later historical runtime profiles should be separate:

```text
hp-a2000 × legacy-dfl-baseline
rtx5880-ada × legacy-dfl-baseline
```

Never compare speed or quality results unless both the source commit and environment profile are recorded.

## Local profile files

Copy `config/machine-profile.example.psd1` into `config/local/`. That directory is ignored by Git.

Recommended filenames:

```text
config/local/hp-a2000-system-py312.psd1
config/local/rtx5880-system-cu130.psd1
config/local/hp-a2000-legacy-dfl.psd1
config/local/rtx5880-legacy-dfl.psd1
```

The first two describe existing system environments. They are useful for diagnostics but do not prove DeepFaceLab compatibility. The latter two will be created only after the historical runtime is identified.

## Artifact layout

Reports must be kept separate:

```text
artifacts/p0/hp-a2000/system-py312/
artifacts/p0/rtx5880-ada/system-cu130/
artifacts/p0/hp-a2000/legacy-dfl-baseline/
artifacts/p0/rtx5880-ada/legacy-dfl-baseline/
```

Do not commit these directories. Reports may contain usernames and local paths and must be redacted before sharing.

## Acceptance policy

P0 requires one complete end-to-end historical baseline first. It does not require both machines to pass before development can continue.

Recommended order:

1. Make scripts pass on `hp-a2000` because Windows PowerShell 5.1 exposes compatibility bugs quickly.
2. Identify and verify one historical DeepFaceLab runtime.
3. Complete extraction, short training, save/resume, merge and DFM export on the most suitable machine.
4. Re-run the same source commit and runtime profile on the second machine where practical.
5. Record hardware-specific differences without treating them as code regressions.

## Role boundaries

| Role | Purpose | Required evidence |
|---|---|---|
| engineering | scripts, diagnostics, compatibility, low-resource behavior | repository and machine checks |
| baseline | frozen historical end-to-end workflow | extraction through DFM consumer load |
| performance | speed, VRAM, resolution and long-run stability | comparable settings and measured reports |

A machine may have more than one role through different profiles.
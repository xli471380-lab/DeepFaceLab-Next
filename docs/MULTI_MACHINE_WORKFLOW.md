# Multi-machine development workflow

DeepFaceLab-Next uses two computers as equal, complete development nodes. They share the same repository, branches, roadmap, and acceptance requirements, while keeping their local runtimes and generated data independent.

The correct model is:

```text
same development work
+ independent local clone
+ independent runtime profile
+ independent artifacts and training data
```

A physical computer is never assigned a permanent project responsibility. Hardware differences may affect what can run efficiently, but they do not define which development work that computer is allowed to perform.

## Shared project state

Both computers use:

- Repository: `xli471380-lab/DeepFaceLab-Next`
- The same remote branches and pull requests
- The same `DEVELOPMENT_PLAN.md`, `PROGRESS.md`, and `NEXT_CHAT_CONTEXT.md`
- The same source commit for any comparison or acceptance run

GitHub is the synchronization boundary for source code and documentation. Virtual environments, CUDA runtimes, datasets, checkpoints, DFM files, generated reports, and media are not synchronized through Git.

## Independent local state

Each computer keeps its own:

- Repository working directory
- Python or portable runtime
- CUDA/cuDNN/TensorRT installation or bundled runtime
- FFmpeg path
- `config/local/*.psd1` profile files
- `artifacts/` reports
- `workspace/` data
- Checkpoints and exported DFM files

The same physical computer can also have multiple independent environment profiles, such as:

```text
hp-a2000 × system-py312
hp-a2000 × legacy-dfl-baseline
rtx5880-ada × comfyui-py313-cu130
rtx5880-ada × legacy-dfl-baseline
```

## Profile naming

Use stable, non-personal labels:

```text
MachineId = 'hp-a2000'
EnvironmentId = 'system-py312'
Role = 'full-development'
```

```text
MachineId = 'rtx5880-ada'
EnvironmentId = 'legacy-dfl-baseline'
Role = 'full-development'
```

`Role` labels the current local profile or validation purpose. It does not assign permanent duties to a computer. Older values such as `engineering`, `baseline`, and `performance` remain accepted for compatibility, but new profiles should normally use `full-development`.

## Local profile files

Copy `config/machine-profile.example.psd1` into `config/local/`. That directory is ignored by Git.

Recommended filenames:

```text
config/local/hp-a2000-system-py312.psd1
config/local/hp-a2000-legacy-dfl.psd1
config/local/rtx5880-comfyui-py313-cu130.psd1
config/local/rtx5880-legacy-dfl.psd1
```

These files describe local paths and environments only. They must not contain project decisions that need to be shared between computers.

## Artifact layout

Reports remain separated by machine and environment:

```text
artifacts/p0/hp-a2000/system-py312/
artifacts/p0/hp-a2000/legacy-dfl-baseline/
artifacts/p0/rtx5880-ada/comfyui-py313-cu130/
artifacts/p0/rtx5880-ada/legacy-dfl-baseline/
```

Do not commit these directories. Reports may contain usernames and local paths and must be redacted before sharing.

## Switching computers

Before leaving computer A:

```powershell
git status
git add <reviewed-files>
git commit -m "descriptive message"
git push origin <current-branch>
```

Also update shared progress/context files when the development state changed.

After moving to computer B:

```powershell
git fetch origin
git switch <current-branch>
git pull --ff-only
git status
```

Do not carry uncommitted source changes between computers by copying folders or cloud-syncing the repository. Commit and push them first.

## Sequential and parallel development

When only one computer is being used at a time, both may work on the same feature branch sequentially.

When both computers are used simultaneously, use separate branches, for example:

```text
agent/p0-runtime-discovery-a2000
agent/p0-runtime-discovery-rtx5880
```

Merge them through reviewed pull requests. Do not let two computers rewrite the same branch history.

## Acceptance policy

Both computers may perform every project task:

- Script and installer development
- Dependency and compatibility investigation
- Extraction and training tests
- Save/resume validation
- Merge and DFM export
- Performance and stability measurements
- Documentation and pull-request work

A result is valid only for the recorded combination of source commit, machine profile, environment profile, and test parameters. Hardware-specific limits are recorded as environment facts, not as permanent work assignments.

P0 requires one complete end-to-end historical baseline first. The second computer can reproduce the same baseline later, but it is not required to be physically available before development continues.

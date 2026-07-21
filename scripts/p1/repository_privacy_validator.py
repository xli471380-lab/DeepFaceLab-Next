#!/usr/bin/env python3
"""CPU-only repository privacy and path-boundary validator for P1.

The validator inspects Git-tracked paths, Git blob identities, and basic file
metadata only. It does not open media, checkpoints, DFM files, embeddings, or
historical runtime files.
"""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
from dataclasses import asdict, dataclass
from datetime import datetime, timezone
from pathlib import Path, PurePosixPath
from typing import Iterable, Mapping, MutableSequence, Sequence

SCHEMA_VERSION = 2
PHASE = "p1_repository_privacy_validation"
FROZEN_BASELINE_COMMIT = "e4b7543ffa1d73b26fce1e31852727f658ba490c"

PROHIBITED_ROOT_PREFIXES = (
    "config/local/",
    "artifacts/",
    "workspace/",
    ".p1-local/",
    ".venv/",
    "venv/",
    "data_src/",
    "data_dst/",
    "aligned/",
    "merged/",
    "merged_mask/",
    "dfm/",
    "model/",
)

PROHIBITED_EXTENSIONS = frozenset(
    {
        ".dfm",
        ".ckpt",
        ".pt",
        ".pth",
        ".safetensors",
        ".h5",
        ".hdf5",
        ".npy",
        ".npz",
        ".pkl",
        ".pickle",
        ".onnx",
        ".mp4",
        ".mov",
        ".avi",
        ".mkv",
        ".webm",
        ".wmv",
        ".zip",
        ".rar",
        ".7z",
        ".tar",
        ".gz",
        ".exe",
        ".dll",
    }
)

SECRET_FILE_NAMES = frozenset(
    {
        ".env",
        ".env.local",
        "credentials.json",
        "credential.json",
        "secrets.json",
        "secret.json",
        "token.json",
        "tokens.json",
        "id_rsa",
        "id_ed25519",
        "known_hosts",
    }
)

TEXT_EXTENSIONS = frozenset(
    {
        ".py",
        ".md",
        ".txt",
        ".ps1",
        ".psd1",
        ".json",
        ".bat",
        ".yml",
        ".yaml",
        ".sh",
    }
)


@dataclass(frozen=True)
class Finding:
    code: str
    severity: str
    path: str
    message: str
    remediation: str
    retry_safe: bool = True
    local_state_may_have_changed: bool = False


@dataclass(frozen=True)
class GrandfatheredArtifact:
    path: str
    blob_sha: str
    reasons: tuple[str, ...]
    baseline_commit: str


class ValidationError(RuntimeError):
    """Operational failure that prevented validation."""


def normalize_repo_path(value: str) -> str:
    """Return a stable relative POSIX-style path for matching and reports."""
    normalized = value.replace("\\", "/").strip()
    while normalized.startswith("./"):
        normalized = normalized[2:]
    normalized = str(PurePosixPath(normalized))
    return "" if normalized == "." else normalized


def _is_under_prohibited_root(path_lower: str) -> str | None:
    candidate = path_lower.rstrip("/") + ("/" if path_lower else "")
    for prefix in PROHIBITED_ROOT_PREFIXES:
        if candidate.startswith(prefix.lower()):
            return prefix
    return None


def _safe_file_size(repo_root: Path, relative_path: str) -> int | None:
    file_path = repo_root / Path(relative_path)
    try:
        if file_path.is_file():
            return file_path.stat().st_size
    except OSError:
        return None
    return None


def _unchanged_frozen_blob(
    relative_path: str,
    *,
    baseline_blob_by_path: Mapping[str, str],
    current_blob_by_path: Mapping[str, str],
) -> str | None:
    baseline_blob = baseline_blob_by_path.get(relative_path)
    current_blob = current_blob_by_path.get(relative_path)
    if baseline_blob and current_blob and baseline_blob == current_blob:
        return baseline_blob
    return None


def scan_tracked_paths(
    repo_root: Path,
    tracked_paths: Iterable[str],
    *,
    max_nontext_bytes: int = 5 * 1024 * 1024,
    baseline_blob_by_path: Mapping[str, str] | None = None,
    current_blob_by_path: Mapping[str, str] | None = None,
    frozen_baseline_commit: str = FROZEN_BASELINE_COMMIT,
    grandfathered_output: MutableSequence[GrandfatheredArtifact] | None = None,
) -> list[Finding]:
    """Inspect tracked path names and metadata without reading file contents.

    Historical binary assets are accepted only when their current Git blob SHA is
    identical to the same path in the frozen upstream baseline. A modified blob at
    a grandfathered path is blocked.
    """
    findings: list[Finding] = []
    seen: set[str] = set()
    baseline_blobs = baseline_blob_by_path or {}
    current_blobs = current_blob_by_path or {}

    for raw_path in tracked_paths:
        relative_path = normalize_repo_path(raw_path)
        if not relative_path or relative_path in seen:
            continue
        seen.add(relative_path)

        path_lower = relative_path.lower()
        name_lower = PurePosixPath(relative_path).name.lower()
        extension = PurePosixPath(relative_path).suffix.lower()
        size_bytes = _safe_file_size(repo_root, relative_path)

        prohibited_root = _is_under_prohibited_root(path_lower)
        if prohibited_root is not None:
            findings.append(
                Finding(
                    code="P1_PRIVACY_PROHIBITED_ROOT",
                    severity="error",
                    path=relative_path,
                    message=(
                        f"Tracked path is inside a local/private root: {prohibited_root}"
                    ),
                    remediation=(
                        "Remove the file from Git tracking, keep it only in the ignored "
                        "local directory, and verify that no sensitive history is pushed."
                    ),
                )
            )

        if name_lower in SECRET_FILE_NAMES:
            findings.append(
                Finding(
                    code="P1_PRIVACY_SECRET_FILENAME",
                    severity="error",
                    path=relative_path,
                    message="Tracked filename matches a credential or secret pattern.",
                    remediation=(
                        "Remove the file from Git, rotate any exposed credential, and use a "
                        "documented local-only configuration path."
                    ),
                    retry_safe=False,
                )
            )

        extension_prohibited = extension in PROHIBITED_EXTENSIONS
        oversized_nontext = (
            size_bytes is not None
            and extension not in TEXT_EXTENSIONS
            and size_bytes > max_nontext_bytes
        )

        # Local/private roots and secret-like names are never grandfathered.
        binary_candidate = (
            prohibited_root is None
            and name_lower not in SECRET_FILE_NAMES
            and (extension_prohibited or oversized_nontext)
        )

        if binary_candidate:
            unchanged_blob = _unchanged_frozen_blob(
                relative_path,
                baseline_blob_by_path=baseline_blobs,
                current_blob_by_path=current_blobs,
            )
            if unchanged_blob is not None:
                if grandfathered_output is not None:
                    reasons: list[str] = []
                    if extension_prohibited:
                        reasons.append(f"historical extension {extension}")
                    if oversized_nontext:
                        reasons.append(
                            f"historical non-text size {size_bytes} bytes"
                        )
                    grandfathered_output.append(
                        GrandfatheredArtifact(
                            path=relative_path,
                            blob_sha=unchanged_blob,
                            reasons=tuple(reasons),
                            baseline_commit=frozen_baseline_commit,
                        )
                    )
                continue

            baseline_blob = baseline_blobs.get(relative_path)
            current_blob = current_blobs.get(relative_path)
            if baseline_blob and current_blob and baseline_blob != current_blob:
                findings.append(
                    Finding(
                        code="P1_PRIVACY_FROZEN_ARTIFACT_CHANGED",
                        severity="error",
                        path=relative_path,
                        message=(
                            "A historical binary path no longer matches the frozen "
                            f"baseline Git blob ({baseline_blob} -> {current_blob})."
                        ),
                        remediation=(
                            "Restore the exact frozen blob or isolate the proposed binary "
                            "change in a separately reviewed migration with explicit hashes, "
                            "licensing, rollback, and regression evidence."
                        ),
                    )
                )
                continue

        if extension_prohibited:
            findings.append(
                Finding(
                    code="P1_PRIVACY_PROHIBITED_EXTENSION",
                    severity="error",
                    path=relative_path,
                    message=f"Tracked file type is prohibited: {extension}",
                    remediation=(
                        "Remove the binary/media/model artifact from Git tracking and store "
                        "it only in an ignored local path."
                    ),
                )
            )

        if oversized_nontext:
            findings.append(
                Finding(
                    code="P1_PRIVACY_OVERSIZED_NON_TEXT",
                    severity="error",
                    path=relative_path,
                    message=(
                        f"Tracked non-text file is {size_bytes} bytes, above the "
                        f"{max_nontext_bytes}-byte boundary."
                    ),
                    remediation=(
                        "Review the file, remove generated/private binaries from Git, or add "
                        "a narrowly documented immutable-baseline exception with tests."
                    ),
                )
            )

    return sorted(findings, key=lambda item: (item.path.lower(), item.code))


def _run_git_bytes(repo_root: Path, arguments: Sequence[str], label: str) -> bytes:
    process = subprocess.run(
        ["git", "-C", str(repo_root), *arguments],
        check=False,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    if process.returncode != 0:
        stderr = process.stderr.decode("utf-8", errors="replace").strip()
        raise ValidationError(
            f"Unable to {label} (exit {process.returncode}): {stderr}"
        )
    return process.stdout


def git_index_blobs(repo_root: Path) -> dict[str, str]:
    """Return stage-0 Git index blob SHAs keyed by normalized path."""
    output = _run_git_bytes(
        repo_root,
        ["ls-files", "-s", "-z"],
        "enumerate Git index blobs",
    )
    records: dict[str, str] = {}
    for raw_entry in output.split(b"\0"):
        if not raw_entry:
            continue
        try:
            metadata_raw, path_raw = raw_entry.split(b"\t", 1)
            metadata = metadata_raw.decode("ascii", errors="strict").split()
            if len(metadata) != 3:
                raise ValueError("unexpected metadata field count")
            _mode, blob_sha, stage = metadata
            if stage != "0":
                raise ValidationError(
                    "The Git index contains an unresolved non-stage-0 entry."
                )
            path = normalize_repo_path(
                path_raw.decode("utf-8", errors="surrogateescape")
            )
        except ValidationError:
            raise
        except Exception as exc:
            raise ValidationError(
                f"Unable to parse a Git index entry: {exc}"
            ) from exc
        records[path] = blob_sha
    return records


def git_tree_blobs(repo_root: Path, commit: str) -> dict[str, str]:
    """Return blob SHAs from one commit tree without reading blob contents."""
    output = _run_git_bytes(
        repo_root,
        ["ls-tree", "-r", "-z", "--full-tree", commit],
        f"enumerate frozen baseline tree {commit}",
    )
    records: dict[str, str] = {}
    for raw_entry in output.split(b"\0"):
        if not raw_entry:
            continue
        try:
            metadata_raw, path_raw = raw_entry.split(b"\t", 1)
            metadata = metadata_raw.decode("ascii", errors="strict").split()
            if len(metadata) != 3:
                raise ValueError("unexpected metadata field count")
            _mode, object_type, object_sha = metadata
            if object_type != "blob":
                continue
            path = normalize_repo_path(
                path_raw.decode("utf-8", errors="surrogateescape")
            )
        except Exception as exc:
            raise ValidationError(
                f"Unable to parse frozen baseline tree entry: {exc}"
            ) from exc
        records[path] = object_sha
    return records


def git_commit(repo_root: Path) -> str | None:
    process = subprocess.run(
        ["git", "-C", str(repo_root), "rev-parse", "HEAD"],
        check=False,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        text=True,
        encoding="utf-8",
        errors="replace",
    )
    if process.returncode != 0:
        return None
    value = process.stdout.strip()
    return value or None


def build_report(
    *,
    repo_root: Path,
    tracked_paths: Sequence[str],
    findings: Sequence[Finding],
    frozen_baseline_commit: str = FROZEN_BASELINE_COMMIT,
    grandfathered: Sequence[GrandfatheredArtifact] = (),
) -> dict[str, object]:
    errors = sum(1 for item in findings if item.severity == "error")
    warnings = sum(1 for item in findings if item.severity == "warning")
    return {
        "schema_version": SCHEMA_VERSION,
        "phase": PHASE,
        "generated_at_utc": datetime.now(timezone.utc).isoformat(),
        "status": "passed" if errors == 0 else "blocked",
        "repository_root": str(repo_root),
        "repository_commit": git_commit(repo_root),
        "frozen_baseline_commit": frozen_baseline_commit,
        "tracked_file_count": len(set(map(normalize_repo_path, tracked_paths)) - {""}),
        "summary": {
            "error_count": errors,
            "warning_count": warnings,
            "finding_count": len(findings),
            "grandfathered_unchanged_binary_count": len(grandfathered),
        },
        "findings": [asdict(item) for item in findings],
        "grandfathered_unchanged_binaries": [
            asdict(item) for item in sorted(grandfathered, key=lambda value: value.path)
        ],
        "safety": {
            "media_contents_read": False,
            "checkpoint_contents_read": False,
            "dfm_contents_read": False,
            "git_blob_contents_read": False,
            "historical_runtime_started": False,
            "gpu_required": False,
            "repository_modified": False,
        },
    }


def write_json_atomic(path: Path, report: dict[str, object]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(path.name + ".partial")
    encoded = json.dumps(report, ensure_ascii=False, indent=2) + "\n"
    try:
        temporary.write_text(encoded, encoding="utf-8")
        os.replace(temporary, path)
    finally:
        try:
            temporary.unlink(missing_ok=True)
        except OSError:
            pass


def parse_args(argv: Sequence[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    default_root = Path(__file__).resolve().parents[2]
    parser.add_argument(
        "--repo-root",
        type=Path,
        default=default_root,
        help="Repository root. Defaults to the script's repository.",
    )
    parser.add_argument(
        "--json-output",
        type=Path,
        default=None,
        help="Optional machine-readable report path.",
    )
    parser.add_argument(
        "--max-nontext-bytes",
        type=int,
        default=5 * 1024 * 1024,
        help="Maximum tracked non-text file size before blocking.",
    )
    parser.add_argument(
        "--frozen-baseline",
        default=FROZEN_BASELINE_COMMIT,
        help="Commit whose unchanged historical binary blobs are grandfathered.",
    )
    return parser.parse_args(argv)


def main(argv: Sequence[str] | None = None) -> int:
    args = parse_args(argv if argv is not None else sys.argv[1:])
    repo_root = args.repo_root.resolve()

    try:
        if args.max_nontext_bytes < 1:
            raise ValidationError("--max-nontext-bytes must be greater than zero.")
        if not (repo_root / ".git").exists():
            raise ValidationError(f"Not a Git worktree: {repo_root}")

        current_blobs = git_index_blobs(repo_root)
        baseline_blobs = git_tree_blobs(repo_root, args.frozen_baseline)
        tracked_paths = sorted(current_blobs)
        grandfathered: list[GrandfatheredArtifact] = []
        findings = scan_tracked_paths(
            repo_root,
            tracked_paths,
            max_nontext_bytes=args.max_nontext_bytes,
            baseline_blob_by_path=baseline_blobs,
            current_blob_by_path=current_blobs,
            frozen_baseline_commit=args.frozen_baseline,
            grandfathered_output=grandfathered,
        )
        report = build_report(
            repo_root=repo_root,
            tracked_paths=tracked_paths,
            findings=findings,
            frozen_baseline_commit=args.frozen_baseline,
            grandfathered=grandfathered,
        )

        if args.json_output is not None:
            output_path = args.json_output
            if not output_path.is_absolute():
                output_path = repo_root / output_path
            write_json_atomic(output_path, report)

        summary = report["summary"]
        assert isinstance(summary, dict)
        print("P1 repository privacy validation")
        print(f"Status: {report['status']}")
        print(f"Tracked files: {report['tracked_file_count']}")
        print(f"Frozen baseline: {args.frozen_baseline}")
        print(
            "Grandfathered unchanged historical binaries: "
            f"{summary['grandfathered_unchanged_binary_count']}"
        )
        print(f"Errors: {summary['error_count']}")
        print(f"Warnings: {summary['warning_count']}")
        for finding in findings:
            print(f"[{finding.code}] {finding.path}: {finding.message}")
            print(f"  Remediation: {finding.remediation}")

        return 0 if report["status"] == "passed" else 2
    except ValidationError as exc:
        print(f"[P1_PRIVACY_OPERATIONAL_ERROR] {exc}", file=sys.stderr)
        return 3
    except Exception as exc:  # pragma: no cover - final safety boundary
        print(
            f"[P1_PRIVACY_UNEXPECTED_ERROR] {type(exc).__name__}: {exc}",
            file=sys.stderr,
        )
        return 4


if __name__ == "__main__":
    raise SystemExit(main())

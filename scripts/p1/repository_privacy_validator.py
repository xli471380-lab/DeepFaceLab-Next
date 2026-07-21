#!/usr/bin/env python3
"""CPU-only repository privacy and path-boundary validator for P1.

The validator inspects Git-tracked paths and basic file metadata only. It does not
open media, checkpoints, DFM files, embeddings, or historical runtime files.
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
from typing import Iterable, Sequence

SCHEMA_VERSION = 1
PHASE = "p1_repository_privacy_validation"

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
        prefix_lower = prefix.lower()
        if candidate.startswith(prefix_lower):
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


def scan_tracked_paths(
    repo_root: Path,
    tracked_paths: Iterable[str],
    *,
    max_nontext_bytes: int = 5 * 1024 * 1024,
) -> list[Finding]:
    """Inspect tracked path names and file sizes without reading file contents."""
    findings: list[Finding] = []
    seen: set[str] = set()

    for raw_path in tracked_paths:
        relative_path = normalize_repo_path(raw_path)
        if not relative_path or relative_path in seen:
            continue
        seen.add(relative_path)

        path_lower = relative_path.lower()
        name_lower = PurePosixPath(relative_path).name.lower()
        extension = PurePosixPath(relative_path).suffix.lower()

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

        if extension in PROHIBITED_EXTENSIONS:
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

        size_bytes = _safe_file_size(repo_root, relative_path)
        if (
            size_bytes is not None
            and extension not in TEXT_EXTENSIONS
            and size_bytes > max_nontext_bytes
        ):
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
                        "a narrowly documented exception with tests."
                    ),
                )
            )

    return sorted(findings, key=lambda item: (item.path.lower(), item.code))


def git_tracked_paths(repo_root: Path) -> list[str]:
    process = subprocess.run(
        ["git", "-C", str(repo_root), "ls-files", "-z"],
        check=False,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    if process.returncode != 0:
        stderr = process.stderr.decode("utf-8", errors="replace").strip()
        raise ValidationError(
            f"Unable to enumerate Git-tracked paths (exit {process.returncode}): {stderr}"
        )
    return [
        item.decode("utf-8", errors="surrogateescape")
        for item in process.stdout.split(b"\0")
        if item
    ]


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
        "tracked_file_count": len(set(map(normalize_repo_path, tracked_paths)) - {""}),
        "summary": {
            "error_count": errors,
            "warning_count": warnings,
            "finding_count": len(findings),
        },
        "findings": [asdict(item) for item in findings],
        "safety": {
            "media_contents_read": False,
            "checkpoint_contents_read": False,
            "dfm_contents_read": False,
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
    return parser.parse_args(argv)


def main(argv: Sequence[str] | None = None) -> int:
    args = parse_args(argv if argv is not None else sys.argv[1:])
    repo_root = args.repo_root.resolve()

    try:
        if args.max_nontext_bytes < 1:
            raise ValidationError("--max-nontext-bytes must be greater than zero.")
        if not (repo_root / ".git").exists():
            raise ValidationError(f"Not a Git worktree: {repo_root}")

        tracked_paths = git_tracked_paths(repo_root)
        findings = scan_tracked_paths(
            repo_root,
            tracked_paths,
            max_nontext_bytes=args.max_nontext_bytes,
        )
        report = build_report(
            repo_root=repo_root,
            tracked_paths=tracked_paths,
            findings=findings,
        )

        if args.json_output is not None:
            output_path = args.json_output
            if not output_path.is_absolute():
                output_path = repo_root / output_path
            write_json_atomic(output_path, report)

        print("P1 repository privacy validation")
        print(f"Status: {report['status']}")
        print(f"Tracked files: {report['tracked_file_count']}")
        print(f"Errors: {report['summary']['error_count']}")  # type: ignore[index]
        print(f"Warnings: {report['summary']['warning_count']}")  # type: ignore[index]
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

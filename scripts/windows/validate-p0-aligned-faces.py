from __future__ import print_function

import json
import os
import pathlib
import sys
import traceback


def safe_text(value):
    try:
        return str(value)
    except Exception:
        return repr(value)


def main():
    if len(sys.argv) != 4:
        raise SystemExit("usage: validate-p0-aligned-faces.py <dfl-root> <input-dir> <aligned-dir>")

    dfl_root = pathlib.Path(sys.argv[1]).resolve()
    input_dir = pathlib.Path(sys.argv[2]).resolve()
    aligned_dir = pathlib.Path(sys.argv[3]).resolve()

    sys.path.insert(0, str(dfl_root))

    result = {
        "schema_version": 1,
        "status": "blocked_not_started",
        "dfl_root": str(dfl_root),
        "input_dir": str(input_dir),
        "aligned_dir": str(aligned_dir),
        "input_count": 0,
        "aligned_count": 0,
        "records": [],
        "errors": [],
        "safety": {
            "tensorflow_imported": False,
            "deepfacelab_main_executed": False,
            "training_started": False,
            "files_modified": False,
        },
    }

    try:
        from DFLIMG import DFLJPG

        allowed_inputs = {".jpg", ".jpeg", ".png", ".webp", ".bmp", ".tif", ".tiff"}
        input_files = sorted(
            path for path in input_dir.iterdir()
            if path.is_file() and path.suffix.lower() in allowed_inputs
        )
        aligned_files = sorted(
            path for path in aligned_dir.iterdir()
            if path.is_file() and path.suffix.lower() == ".jpg"
        )

        result["input_count"] = len(input_files)
        result["aligned_count"] = len(aligned_files)

        expected_names = {path.stem + "_0.jpg": path.name for path in input_files}
        actual_names = {path.name for path in aligned_files}

        missing = sorted(set(expected_names.keys()) - actual_names)
        unexpected = sorted(actual_names - set(expected_names.keys()))
        if missing:
            result["errors"].append({"type": "missing_aligned_files", "files": missing})
        if unexpected:
            result["errors"].append({"type": "unexpected_aligned_files", "files": unexpected})

        for aligned_path in aligned_files:
            record = {
                "aligned_file": aligned_path.name,
                "size_bytes": int(aligned_path.stat().st_size),
                "load_succeeded": False,
                "has_data": False,
                "source_filename": None,
                "expected_source_filename": expected_names.get(aligned_path.name),
                "face_type": None,
                "valid": False,
            }
            try:
                dflimg = DFLJPG.load(aligned_path)
                record["load_succeeded"] = dflimg is not None
                if dflimg is not None:
                    record["has_data"] = bool(dflimg.has_data())
                    record["source_filename"] = safe_text(dflimg.get_source_filename())
                    record["face_type"] = safe_text(dflimg.get_face_type())

                record["valid"] = bool(
                    record["size_bytes"] > 0
                    and record["load_succeeded"]
                    and record["has_data"]
                    and record["expected_source_filename"] is not None
                    and record["source_filename"] == record["expected_source_filename"]
                    and record["face_type"] == "whole_face"
                )
            except BaseException as exc:
                record["error_type"] = type(exc).__name__
                record["error"] = safe_text(exc)
                record["traceback"] = traceback.format_exc()
            result["records"].append(record)

        all_records_valid = bool(result["records"]) and all(item.get("valid") for item in result["records"])
        counts_match = len(input_files) == len(aligned_files) and len(input_files) > 0
        result["status"] = "passed" if counts_match and not result["errors"] and all_records_valid else "blocked_invalid_faceset"
    except BaseException as exc:
        result["status"] = "blocked_validator_exception"
        result["errors"].append({
            "type": type(exc).__name__,
            "error": safe_text(exc),
            "traceback": traceback.format_exc(),
        })

    print("__DFLNEXT_FACESET_VALIDATION_JSON_BEGIN__")
    print(json.dumps(result, sort_keys=True))
    print("__DFLNEXT_FACESET_VALIDATION_JSON_END__")
    sys.stdout.flush()
    return 0 if result.get("status") == "passed" else 1


if __name__ == "__main__":
    sys.exit(main())

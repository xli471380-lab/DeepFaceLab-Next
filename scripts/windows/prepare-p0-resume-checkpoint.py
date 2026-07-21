from __future__ import print_function

import hashlib
import json
import os
import pathlib
import pickle
import sys
import tempfile
import traceback


BEGIN = "__DFLNEXT_RESUME_PREPARE_JSON_BEGIN__"
END = "__DFLNEXT_RESUME_PREPARE_JSON_END__"


def sha256_file(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        while True:
            chunk = stream.read(1024 * 1024)
            if not chunk:
                break
            digest.update(chunk)
    return digest.hexdigest().upper()


def normalize(value):
    try:
        if hasattr(value, "item"):
            value = value.item()
    except Exception:
        pass

    if isinstance(value, dict):
        return {str(key): normalize(item) for key, item in value.items()}
    if isinstance(value, (list, tuple)):
        return [normalize(item) for item in value]
    if isinstance(value, pathlib.Path):
        return str(value)
    if isinstance(value, (str, int, float, bool)) or value is None:
        return value
    return repr(value)


def inventory(directory):
    records = []
    for path in sorted(directory.iterdir(), key=lambda item: item.name.lower()):
        if path.is_file():
            records.append({
                "name": path.name,
                "size_bytes": int(path.stat().st_size),
                "sha256": sha256_file(path),
            })
    return records


def by_name(records):
    return {record["name"]: record for record in records}


def load_model_data(path):
    if not path.is_file() or path.stat().st_size <= 0:
        raise RuntimeError("Missing model data file: %s" % path)
    value = pickle.loads(path.read_bytes())
    if not isinstance(value, dict):
        raise RuntimeError("Model data is not a dictionary: %s" % path)
    return value


def dump_atomic(path, value):
    parent = str(path.parent)
    handle, temp_name = tempfile.mkstemp(
        prefix=path.name + ".",
        suffix=".tmp",
        dir=parent,
    )
    try:
        with os.fdopen(handle, "wb") as stream:
            stream.write(pickle.dumps(value, protocol=pickle.HIGHEST_PROTOCOL))
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temp_name, str(path))
    except BaseException:
        try:
            os.unlink(temp_name)
        except OSError:
            pass
        raise


def main():
    if len(sys.argv) != 6:
        raise SystemExit(
            "usage: prepare-p0-resume-checkpoint.py "
            "<accepted-dir> <staging-dir> <model-prefix> "
            "<expected-before-iter> <target-iter>"
        )

    accepted_dir = pathlib.Path(sys.argv[1]).resolve()
    staging_dir = pathlib.Path(sys.argv[2]).resolve()
    prefix = sys.argv[3]
    expected_before = int(sys.argv[4])
    target_iter = int(sys.argv[5])
    data_name = prefix + "_data.dat"

    result = {
        "schema_version": 1,
        "status": "blocked_not_started",
        "accepted_dir": str(accepted_dir),
        "staging_dir": str(staging_dir),
        "model_prefix": prefix,
        "expected_before_iteration": expected_before,
        "target_iteration": target_iter,
        "before_iteration": None,
        "before_loss_history_count": None,
        "before_target_iter": None,
        "after_iteration": None,
        "after_loss_history_count": None,
        "after_target_iter": None,
        "file_set_preserved": False,
        "non_data_files_preserved": False,
        "original_checkpoint_unchanged": False,
        "options_preserved_except_target_iter": False,
        "loss_history_preserved": False,
        "other_model_data_preserved": False,
        "data_file_changed": False,
        "accepted_files": [],
        "staging_files_before": [],
        "staging_files_after": [],
        "errors": [],
        "safety": {
            "tensorflow_imported": False,
            "deepfacelab_main_executed": False,
            "accepted_checkpoint_modified": False,
            "staging_checkpoint_only": True,
            "atomic_data_file_replace": False,
        },
    }

    try:
        if target_iter <= expected_before:
            result["errors"].append({"type": "target_not_greater_than_before"})
        if not accepted_dir.is_dir():
            result["errors"].append({"type": "missing_accepted_directory"})
        if not staging_dir.is_dir():
            result["errors"].append({"type": "missing_staging_directory"})

        if not result["errors"]:
            accepted_before = inventory(accepted_dir)
            staging_before = inventory(staging_dir)
            result["accepted_files"] = accepted_before
            result["staging_files_before"] = staging_before

            accepted_names = [item["name"] for item in accepted_before]
            staging_names = [item["name"] for item in staging_before]
            if accepted_names != staging_names:
                result["errors"].append({
                    "type": "staging_file_set_mismatch_before_patch",
                    "accepted": accepted_names,
                    "staging": staging_names,
                })

            accepted_map = by_name(accepted_before)
            staging_before_map = by_name(staging_before)
            for name in accepted_names:
                if name not in staging_before_map:
                    continue
                if accepted_map[name]["sha256"] != staging_before_map[name]["sha256"]:
                    result["errors"].append({
                        "type": "staging_hash_mismatch_before_patch",
                        "file": name,
                    })

            accepted_data_path = accepted_dir / data_name
            staging_data_path = staging_dir / data_name
            accepted_data = load_model_data(accepted_data_path)
            staging_data = load_model_data(staging_data_path)

            if normalize(accepted_data) != normalize(staging_data):
                result["errors"].append({"type": "staging_model_data_mismatch_before_patch"})

            before_iter = int(staging_data.get("iter", -1))
            before_history = list(staging_data.get("loss_history", []))
            options = staging_data.get("options")
            if not isinstance(options, dict):
                result["errors"].append({"type": "missing_options_dictionary"})
                options = {}

            before_target = options.get("target_iter")
            result["before_iteration"] = before_iter
            result["before_loss_history_count"] = len(before_history)
            result["before_target_iter"] = before_target

            if before_iter != expected_before:
                result["errors"].append({
                    "type": "unexpected_before_iteration",
                    "expected": expected_before,
                    "actual": before_iter,
                })
            if len(before_history) != expected_before:
                result["errors"].append({
                    "type": "unexpected_before_loss_history_count",
                    "expected": expected_before,
                    "actual": len(before_history),
                })
            try:
                before_target_int = int(before_target)
            except Exception:
                before_target_int = None
            if before_target_int != expected_before:
                result["errors"].append({
                    "type": "unexpected_before_target_iter",
                    "expected": expected_before,
                    "actual": before_target,
                })

            if not result["errors"]:
                original_non_options = {
                    key: value for key, value in staging_data.items() if key != "options"
                }
                original_options = dict(options)
                original_options_without_target = dict(original_options)
                original_options_without_target.pop("target_iter", None)

                staging_data["options"] = dict(options)
                staging_data["options"]["target_iter"] = target_iter
                dump_atomic(staging_data_path, staging_data)
                result["safety"]["atomic_data_file_replace"] = True

                patched_data = load_model_data(staging_data_path)
                patched_options = patched_data.get("options")
                if not isinstance(patched_options, dict):
                    result["errors"].append({"type": "patched_options_not_dictionary"})
                    patched_options = {}

                patched_iter = int(patched_data.get("iter", -1))
                patched_history = list(patched_data.get("loss_history", []))
                patched_target = patched_options.get("target_iter")
                result["after_iteration"] = patched_iter
                result["after_loss_history_count"] = len(patched_history)
                result["after_target_iter"] = patched_target

                patched_options_without_target = dict(patched_options)
                patched_options_without_target.pop("target_iter", None)
                result["options_preserved_except_target_iter"] = (
                    normalize(original_options_without_target)
                    == normalize(patched_options_without_target)
                    and int(patched_target) == target_iter
                )
                result["loss_history_preserved"] = (
                    normalize(before_history) == normalize(patched_history)
                )
                patched_non_options = {
                    key: value for key, value in patched_data.items() if key != "options"
                }
                result["other_model_data_preserved"] = (
                    normalize(original_non_options) == normalize(patched_non_options)
                )

                if patched_iter != expected_before:
                    result["errors"].append({"type": "iteration_changed_during_prepare"})
                if not result["options_preserved_except_target_iter"]:
                    result["errors"].append({"type": "options_changed_beyond_target_iter"})
                if not result["loss_history_preserved"]:
                    result["errors"].append({"type": "loss_history_changed_during_prepare"})
                if not result["other_model_data_preserved"]:
                    result["errors"].append({"type": "other_model_data_changed_during_prepare"})

            accepted_after = inventory(accepted_dir)
            staging_after = inventory(staging_dir)
            result["staging_files_after"] = staging_after
            result["original_checkpoint_unchanged"] = accepted_before == accepted_after
            result["safety"]["accepted_checkpoint_modified"] = not result[
                "original_checkpoint_unchanged"
            ]

            staging_after_map = by_name(staging_after)
            result["file_set_preserved"] = (
                [item["name"] for item in staging_before]
                == [item["name"] for item in staging_after]
            )
            non_data_preserved = True
            for name, before_record in staging_before_map.items():
                if name == data_name:
                    continue
                after_record = staging_after_map.get(name)
                if after_record is None or before_record["sha256"] != after_record["sha256"]:
                    non_data_preserved = False
                    break
            result["non_data_files_preserved"] = non_data_preserved
            if data_name in staging_before_map and data_name in staging_after_map:
                result["data_file_changed"] = (
                    staging_before_map[data_name]["sha256"]
                    != staging_after_map[data_name]["sha256"]
                )

            if not result["original_checkpoint_unchanged"]:
                result["errors"].append({"type": "accepted_checkpoint_changed"})
            if not result["file_set_preserved"]:
                result["errors"].append({"type": "staging_file_set_changed"})
            if not result["non_data_files_preserved"]:
                result["errors"].append({"type": "non_data_checkpoint_file_changed"})
            if not result["data_file_changed"]:
                result["errors"].append({"type": "target_data_file_did_not_change"})

        result["status"] = "passed" if not result["errors"] else "blocked_invalid_prepare"
    except BaseException as exc:
        result["status"] = "blocked_prepare_exception"
        result["errors"].append({
            "type": type(exc).__name__,
            "error": str(exc),
            "traceback": traceback.format_exc(),
        })

    print(BEGIN)
    print(json.dumps(result, sort_keys=True))
    print(END)
    sys.stdout.flush()
    return 0 if result.get("status") == "passed" else 1


if __name__ == "__main__":
    sys.exit(main())

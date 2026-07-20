from __future__ import print_function

import hashlib
import json
import math
import pathlib
import pickle
import sys
import traceback


BEGIN = "__DFLNEXT_RESUME_CHECKPOINT_JSON_BEGIN__"
END = "__DFLNEXT_RESUME_CHECKPOINT_JSON_END__"


def sha256_file(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        while True:
            chunk = stream.read(1024 * 1024)
            if not chunk:
                break
            digest.update(chunk)
    return digest.hexdigest().upper()


def scalar(value):
    try:
        if hasattr(value, "item"):
            return value.item()
    except Exception:
        pass
    return value


def normalize(value):
    value = scalar(value)
    if isinstance(value, dict):
        return {str(key): normalize(item) for key, item in value.items()}
    if isinstance(value, (list, tuple)):
        return [normalize(item) for item in value]
    if isinstance(value, pathlib.Path):
        return str(value)
    if isinstance(value, (str, int, float, bool)) or value is None:
        return value
    return repr(value)


def finite_loss_history(history, errors, label):
    for index, row in enumerate(history):
        values = list(row)
        if len(values) != 2:
            errors.append({
                "type": "unexpected_loss_width",
                "checkpoint": label,
                "index": index,
                "count": len(values),
            })
            continue
        for value in values:
            try:
                if not math.isfinite(float(value)):
                    raise ValueError("non-finite")
            except Exception:
                errors.append({
                    "type": "non_finite_loss",
                    "checkpoint": label,
                    "index": index,
                    "value": repr(value),
                })


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


def load_model_data(directory, prefix):
    path = directory / (prefix + "_data.dat")
    if not path.is_file() or path.stat().st_size <= 0:
        raise RuntimeError("Missing model data file: %s" % path)
    return pickle.loads(path.read_bytes())


def main():
    if len(sys.argv) != 6:
        raise SystemExit(
            "usage: validate-p0-resume-checkpoint.py "
            "<before-dir> <resumed-dir> <model-prefix> "
            "<expected-before-iter> <expected-after-iter>"
        )

    before_dir = pathlib.Path(sys.argv[1]).resolve()
    resumed_dir = pathlib.Path(sys.argv[2]).resolve()
    prefix = sys.argv[3]
    expected_before = int(sys.argv[4])
    expected_after = int(sys.argv[5])

    result = {
        "schema_version": 1,
        "status": "blocked_not_started",
        "before_dir": str(before_dir),
        "resumed_dir": str(resumed_dir),
        "model_prefix": prefix,
        "expected_before_iteration": expected_before,
        "expected_after_iteration": expected_after,
        "before_iteration": None,
        "after_iteration": None,
        "before_loss_history_count": None,
        "after_loss_history_count": None,
        "prior_loss_history_preserved": False,
        "options_preserved_except_target_iter": False,
        "changed_weight_files": [],
        "before_files": [],
        "after_files": [],
        "errors": [],
        "safety": {
            "tensorflow_imported": False,
            "deepfacelab_main_executed": False,
            "checkpoint_files_modified": False,
        },
    }

    try:
        if not before_dir.is_dir():
            result["errors"].append({"type": "missing_before_directory"})
        if not resumed_dir.is_dir():
            result["errors"].append({"type": "missing_resumed_directory"})

        if not result["errors"]:
            before_files = inventory(before_dir)
            after_files = inventory(resumed_dir)
            result["before_files"] = before_files
            result["after_files"] = after_files

            before_names = [item["name"] for item in before_files]
            after_names = [item["name"] for item in after_files]
            if before_names != after_names:
                result["errors"].append({
                    "type": "checkpoint_file_set_changed",
                    "before": before_names,
                    "after": after_names,
                })

            if any(name.lower().endswith(".dfm") for name in after_names):
                result["errors"].append({"type": "unexpected_dfm_before_export_gate"})

            required_suffixes = [
                "data.dat",
                "summary.txt",
                "encoder.npy",
                "inter.npy",
                "decoder_src.npy",
                "decoder_dst.npy",
                "src_dst_opt.npy",
            ]
            for suffix in required_suffixes:
                name = prefix + "_" + suffix
                if name not in after_names:
                    result["errors"].append({
                        "type": "missing_resumed_checkpoint_file",
                        "file": name,
                    })

            before_data = load_model_data(before_dir, prefix)
            after_data = load_model_data(resumed_dir, prefix)

            before_iter = int(before_data.get("iter", -1))
            after_iter = int(after_data.get("iter", -1))
            result["before_iteration"] = before_iter
            result["after_iteration"] = after_iter

            if before_iter != expected_before:
                result["errors"].append({
                    "type": "unexpected_before_iteration",
                    "expected": expected_before,
                    "actual": before_iter,
                })
            if after_iter != expected_after:
                result["errors"].append({
                    "type": "unexpected_after_iteration",
                    "expected": expected_after,
                    "actual": after_iter,
                })
            if after_iter <= before_iter:
                result["errors"].append({"type": "iteration_did_not_advance"})

            before_history = list(before_data.get("loss_history", []))
            after_history = list(after_data.get("loss_history", []))
            result["before_loss_history_count"] = len(before_history)
            result["after_loss_history_count"] = len(after_history)

            if len(before_history) != before_iter:
                result["errors"].append({"type": "before_loss_history_mismatch"})
            if len(after_history) != after_iter:
                result["errors"].append({"type": "after_loss_history_mismatch"})

            finite_loss_history(before_history, result["errors"], "before")
            finite_loss_history(after_history, result["errors"], "after")

            before_history_normalized = normalize(before_history)
            after_prior_normalized = normalize(after_history[:len(before_history)])
            prior_preserved = before_history_normalized == after_prior_normalized
            result["prior_loss_history_preserved"] = prior_preserved
            if not prior_preserved:
                result["errors"].append({"type": "prior_loss_history_changed"})

            before_options = normalize(before_data.get("options", {}))
            after_options = normalize(after_data.get("options", {}))
            before_target = before_options.get("target_iter")
            after_target = after_options.get("target_iter")
            before_without_target = dict(before_options)
            after_without_target = dict(after_options)
            before_without_target.pop("target_iter", None)
            after_without_target.pop("target_iter", None)

            options_preserved = (
                before_without_target == after_without_target
                and int(before_target) == expected_before
                and int(after_target) == expected_after
            )
            result["options_preserved_except_target_iter"] = options_preserved
            if not options_preserved:
                result["errors"].append({
                    "type": "resume_options_changed",
                    "before_target_iter": before_target,
                    "after_target_iter": after_target,
                })

            before_by_name = {item["name"]: item for item in before_files}
            after_by_name = {item["name"]: item for item in after_files}
            weight_suffixes = [
                "encoder.npy",
                "inter.npy",
                "decoder_src.npy",
                "decoder_dst.npy",
                "src_dst_opt.npy",
            ]
            changed = []
            for suffix in weight_suffixes:
                name = prefix + "_" + suffix
                if (
                    name in before_by_name
                    and name in after_by_name
                    and before_by_name[name]["sha256"] != after_by_name[name]["sha256"]
                ):
                    changed.append(name)
            result["changed_weight_files"] = changed
            if not changed:
                result["errors"].append({"type": "no_weight_or_optimizer_file_changed"})

        result["status"] = "passed" if not result["errors"] else "blocked_invalid_resume"
    except BaseException as exc:
        result["status"] = "blocked_validator_exception"
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

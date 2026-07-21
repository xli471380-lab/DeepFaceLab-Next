from __future__ import print_function

import hashlib
import json
import math
import pathlib
import pickle
import sys
import traceback


BEGIN = "__DFLNEXT_TRAINING_CHECKPOINT_JSON_BEGIN__"
END = "__DFLNEXT_TRAINING_CHECKPOINT_JSON_END__"


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


def same_value(actual, expected):
    actual = scalar(actual)
    if isinstance(expected, float):
        try:
            return abs(float(actual) - expected) <= 1e-9
        except Exception:
            return False
    if isinstance(expected, bool):
        return isinstance(actual, bool) and actual is expected
    if isinstance(expected, int):
        try:
            return int(actual) == expected
        except Exception:
            return False
    return actual == expected


def main():
    if len(sys.argv) != 4:
        raise SystemExit(
            "usage: validate-p0-training-checkpoint.py "
            "<model-dir> <model-prefix> <expected-iter>"
        )

    model_dir = pathlib.Path(sys.argv[1]).resolve()
    prefix = sys.argv[2]
    expected_iter = int(sys.argv[3])

    result = {
        "schema_version": 1,
        "status": "blocked_not_started",
        "model_dir": str(model_dir),
        "model_prefix": prefix,
        "expected_iteration": expected_iter,
        "iteration": None,
        "loss_history_count": None,
        "files": [],
        "option_checks": [],
        "errors": [],
        "safety": {
            "tensorflow_imported": False,
            "deepfacelab_main_executed": False,
            "checkpoint_files_modified": False,
        },
    }

    try:
        if not model_dir.is_dir():
            result["errors"].append({"type": "missing_model_directory"})
        else:
            expected_suffixes = [
                "data.dat",
                "summary.txt",
                "encoder.npy",
                "inter.npy",
                "decoder_src.npy",
                "decoder_dst.npy",
                "src_dst_opt.npy",
            ]
            expected_names = [prefix + "_" + suffix for suffix in expected_suffixes]

            for name in expected_names:
                path = model_dir / name
                record = {
                    "name": name,
                    "exists": path.is_file(),
                    "size_bytes": int(path.stat().st_size) if path.is_file() else 0,
                    "sha256": sha256_file(path) if path.is_file() else None,
                }
                result["files"].append(record)
                if not record["exists"] or record["size_bytes"] <= 0:
                    result["errors"].append({
                        "type": "missing_or_empty_checkpoint_file",
                        "file": name,
                    })

            unexpected_dfm = sorted(path.name for path in model_dir.glob("*.dfm"))
            if unexpected_dfm:
                result["errors"].append({
                    "type": "unexpected_dfm_before_export_gate",
                    "files": unexpected_dfm,
                })

            data_path = model_dir / (prefix + "_data.dat")
            if data_path.is_file() and data_path.stat().st_size > 0:
                model_data = pickle.loads(data_path.read_bytes())
                iteration = int(model_data.get("iter", -1))
                result["iteration"] = iteration
                if iteration != expected_iter:
                    result["errors"].append({
                        "type": "unexpected_iteration",
                        "expected": expected_iter,
                        "actual": iteration,
                    })

                loss_history = model_data.get("loss_history", [])
                result["loss_history_count"] = len(loss_history)
                if len(loss_history) != iteration:
                    result["errors"].append({
                        "type": "loss_history_length_mismatch",
                        "iteration": iteration,
                        "loss_history_count": len(loss_history),
                    })

                for index, row in enumerate(loss_history):
                    values = list(row)
                    if len(values) != 2:
                        result["errors"].append({
                            "type": "unexpected_loss_width",
                            "index": index,
                            "count": len(values),
                        })
                        continue
                    for value in values:
                        try:
                            if not math.isfinite(float(value)):
                                raise ValueError("non-finite")
                        except Exception:
                            result["errors"].append({
                                "type": "non_finite_loss",
                                "index": index,
                                "value": repr(value),
                            })

                options = model_data.get("options", {})
                expected_options = {
                    "autobackup_hour": 0,
                    "write_preview_history": False,
                    "target_iter": expected_iter,
                    "random_src_flip": False,
                    "random_dst_flip": False,
                    "batch_size": 2,
                    "resolution": 96,
                    "face_type": "wf",
                    "archi": "df",
                    "ae_dims": 64,
                    "e_dims": 32,
                    "d_dims": 32,
                    "d_mask_dims": 16,
                    "masked_training": True,
                    "eyes_mouth_prio": False,
                    "uniform_yaw": False,
                    "blur_out_mask": False,
                    "models_opt_on_gpu": True,
                    "adabelief": False,
                    "lr_dropout": "n",
                    "random_warp": True,
                    "random_hsv_power": 0.0,
                    "gan_power": 0.0,
                    "true_face_power": 0.0,
                    "face_style_power": 0.0,
                    "bg_style_power": 0.0,
                    "ct_mode": "none",
                    "clipgrad": False,
                    "pretrain": False,
                }

                for name in sorted(expected_options):
                    expected = expected_options[name]
                    present = name in options
                    actual = scalar(options.get(name)) if present else None
                    matched = present and same_value(actual, expected)
                    result["option_checks"].append({
                        "name": name,
                        "present": present,
                        "expected": expected,
                        "actual": actual,
                        "matched": matched,
                    })
                    if not matched:
                        result["errors"].append({
                            "type": "checkpoint_option_mismatch",
                            "name": name,
                            "expected": expected,
                            "actual": actual,
                        })

            summary_path = model_dir / (prefix + "_summary.txt")
            if summary_path.is_file():
                summary_text = summary_path.read_text(encoding="utf-8", errors="replace")
                if prefix not in summary_text:
                    result["errors"].append({"type": "summary_model_name_missing"})
                if str(expected_iter) not in summary_text:
                    result["errors"].append({"type": "summary_iteration_missing"})

        result["status"] = "passed" if not result["errors"] else "blocked_invalid_checkpoint"
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

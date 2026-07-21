from __future__ import print_function

import argparse
import builtins
import hashlib
import json
import multiprocessing
import os
import pathlib
import sys
import traceback


BEGIN = "__DFLNEXT_DFM_EXPORT_JSON_BEGIN__"
END = "__DFLNEXT_DFM_EXPORT_JSON_END__"
EXPECTED_EXPORT_PROMPT = "[n] Export quantized? ( y/n ?:help ) :"
_SKIP_PENDING_COUNT = 0
_EXPECTED_EXPORT_PROMPT_COUNT = 0
_UNEXPECTED_PROMPT_COUNT = 0
_UNEXPECTED_PROMPTS = []


def sha256_file(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        while True:
            chunk = stream.read(1024 * 1024)
            if not chunk:
                break
            digest.update(chunk)
    return digest.hexdigest().upper()


def deterministic_skip_pending(self):
    global _SKIP_PENDING_COUNT
    _SKIP_PENDING_COUNT += 1
    print("DFLNEXT fixed-model exporter: skipped interactive stdin drain.")
    sys.stdout.flush()
    return None


def deterministic_export_input(prompt=""):
    global _EXPECTED_EXPORT_PROMPT_COUNT
    global _UNEXPECTED_PROMPT_COUNT
    global _UNEXPECTED_PROMPTS

    normalized = str(prompt).strip()
    if normalized == EXPECTED_EXPORT_PROMPT:
        _EXPECTED_EXPORT_PROMPT_COUNT += 1
        print(
            "DFLNEXT fixed-model exporter: Export quantized? "
            "[deterministic response: n]"
        )
        sys.stdout.flush()
        return "n"

    _UNEXPECTED_PROMPT_COUNT += 1
    _UNEXPECTED_PROMPTS.append(str(prompt))
    raise RuntimeError(
        "Unexpected blocking DeepFaceLab prompt during fixed-model export: %s"
        % prompt
    )


def main():
    global _SKIP_PENDING_COUNT
    global _EXPECTED_EXPORT_PROMPT_COUNT
    global _UNEXPECTED_PROMPT_COUNT
    global _UNEXPECTED_PROMPTS

    parser = argparse.ArgumentParser()
    parser.add_argument("--dfl-root", required=True)
    parser.add_argument("--model-dir", required=True)
    parser.add_argument("--model-class", default="SAEHD")
    parser.add_argument("--model-name", required=True)
    parser.add_argument("--expected-iteration", type=int, required=True)
    args = parser.parse_args()

    dfl_root = pathlib.Path(args.dfl_root).resolve()
    model_dir = pathlib.Path(args.model_dir).resolve()
    model_prefix = "%s_%s" % (args.model_name, args.model_class)
    expected_dfm = model_dir / (model_prefix + "_model.dfm")

    result = {
        "schema_version": 2,
        "status": "blocked_not_started",
        "dfl_root": str(dfl_root),
        "model_dir": str(model_dir),
        "model_class": args.model_class,
        "model_name": args.model_name,
        "model_prefix": model_prefix,
        "expected_iteration": args.expected_iteration,
        "actual_iteration": None,
        "dfm_path": str(expected_dfm),
        "dfm_exists": False,
        "dfm_size_bytes": 0,
        "dfm_sha256": None,
        "quantized_export": False,
        "expected_export_prompt": EXPECTED_EXPORT_PROMPT,
        "expected_export_prompt_count": 0,
        "unexpected_prompt_count": 0,
        "unexpected_prompts": [],
        "stdin_drain_skip_count": 0,
        "errors": [],
        "safety": {
            "cpu_only": True,
            "fixed_model_name": True,
            "training_started": False,
            "merge_started": False,
            "historical_runtime_modified": False,
            "only_expected_export_prompt_allowed": True,
        },
    }

    original_cwd = os.getcwd()
    original_input = builtins.input
    interact_class = None
    original_input_skip_pending = None
    model = None

    try:
        if not dfl_root.is_dir():
            raise RuntimeError("DeepFaceLab root does not exist: %s" % dfl_root)
        if not model_dir.is_dir():
            raise RuntimeError("Model directory does not exist: %s" % model_dir)
        if expected_dfm.exists():
            raise RuntimeError("Expected DFM path already exists: %s" % expected_dfm)

        os.chdir(str(dfl_root))
        if str(dfl_root) not in sys.path:
            sys.path.insert(0, str(dfl_root))

        try:
            multiprocessing.set_start_method("spawn")
        except RuntimeError:
            pass

        from core.interact import interact as interact_object

        interact_class = type(interact_object)
        original_input_skip_pending = interact_class.input_skip_pending
        interact_class.input_skip_pending = deterministic_skip_pending
        builtins.input = deterministic_export_input

        from core.leras import nn

        nn.initialize_main_env()

        from core import osex
        import models

        osex.set_process_lowest_prio()

        print("DFLNEXT fixed-model exporter: model %s." % model_prefix)
        print("DFLNEXT fixed-model exporter: official CPU-only export path.")
        print("DFLNEXT fixed-model exporter: quantized export fixed to no.")
        sys.stdout.flush()

        model = models.import_model(args.model_class)(
            is_exporting=True,
            saved_models_path=model_dir,
            force_model_name=args.model_name,
            cpu_only=True,
        )

        actual_iteration = int(model.get_iter())
        result["actual_iteration"] = actual_iteration
        if actual_iteration != args.expected_iteration:
            raise RuntimeError(
                "Unexpected model iteration: expected %d, actual %d"
                % (args.expected_iteration, actual_iteration)
            )

        model.export_dfm()

        if not expected_dfm.is_file():
            raise RuntimeError(
                "DFM export did not create the expected file: %s" % expected_dfm
            )
        if expected_dfm.stat().st_size <= 0:
            raise RuntimeError("DFM export created an empty file: %s" % expected_dfm)

        result["dfm_exists"] = True
        result["dfm_size_bytes"] = int(expected_dfm.stat().st_size)
        result["dfm_sha256"] = sha256_file(expected_dfm)
        result["status"] = "passed"
    except BaseException as exc:
        result["status"] = "blocked_export_exception"
        result["errors"].append(
            {
                "type": type(exc).__name__,
                "error": str(exc),
                "traceback": traceback.format_exc(),
            }
        )
    finally:
        if model is not None:
            try:
                model.finalize()
            except BaseException as exc:
                result["errors"].append(
                    {
                        "type": "finalize_error",
                        "error": str(exc),
                        "traceback": traceback.format_exc(),
                    }
                )
                result["status"] = "blocked_finalize_exception"
        if interact_class is not None and original_input_skip_pending is not None:
            interact_class.input_skip_pending = original_input_skip_pending
        builtins.input = original_input
        os.chdir(original_cwd)

    result["expected_export_prompt_count"] = _EXPECTED_EXPORT_PROMPT_COUNT
    result["unexpected_prompt_count"] = _UNEXPECTED_PROMPT_COUNT
    result["unexpected_prompts"] = list(_UNEXPECTED_PROMPTS)
    result["stdin_drain_skip_count"] = _SKIP_PENDING_COUNT

    if result["status"] == "passed":
        if _EXPECTED_EXPORT_PROMPT_COUNT != 1:
            result["status"] = "blocked_expected_export_prompt_count"
            result["errors"].append(
                {
                    "type": "expected_export_prompt_count",
                    "actual": _EXPECTED_EXPORT_PROMPT_COUNT,
                    "expected": 1,
                }
            )
        if _UNEXPECTED_PROMPT_COUNT != 0:
            result["status"] = "blocked_unexpected_prompt"
            result["errors"].append(
                {
                    "type": "unexpected_prompt_count",
                    "actual": _UNEXPECTED_PROMPT_COUNT,
                    "expected": 0,
                    "prompts": list(_UNEXPECTED_PROMPTS),
                }
            )
        if _SKIP_PENDING_COUNT != 1:
            result["status"] = "blocked_unexpected_stdin_drain_count"
            result["errors"].append(
                {
                    "type": "stdin_drain_skip_count",
                    "actual": _SKIP_PENDING_COUNT,
                    "expected": 1,
                }
            )

    print(BEGIN)
    print(json.dumps(result, sort_keys=True))
    print(END)
    sys.stdout.flush()
    return 0 if result.get("status") == "passed" else 1


if __name__ == "__main__":
    sys.exit(main())

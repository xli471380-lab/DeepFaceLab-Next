from __future__ import print_function

import hashlib
import json
import pathlib
import pickle
import sys
import traceback


BEGIN = "__DFLNEXT_DFM_VALIDATION_JSON_BEGIN__"
END = "__DFLNEXT_DFM_VALIDATION_JSON_END__"
EXPECTED_INPUTS = {"in_face"}
EXPECTED_OUTPUTS = {"out_face_mask", "out_celeb_face", "out_celeb_face_mask"}


def sha256_file(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        while True:
            chunk = stream.read(1024 * 1024)
            if not chunk:
                break
            digest.update(chunk)
    return digest.hexdigest().upper()


def normalize_tensor_name(value):
    return str(value).split(":", 1)[0]


def load_model_iteration(model_dir, model_prefix):
    data_path = model_dir / (model_prefix + "_data.dat")
    if not data_path.is_file() or data_path.stat().st_size <= 0:
        raise RuntimeError("Missing model data file: %s" % data_path)
    value = pickle.loads(data_path.read_bytes())
    if not isinstance(value, dict):
        raise RuntimeError("Model data is not a dictionary: %s" % data_path)
    return int(value.get("iter", -1))


def main():
    if len(sys.argv) != 5:
        raise SystemExit(
            "usage: validate-p0-dfm-export.py "
            "<staging-model-dir> <model-prefix> <expected-iteration> <expected-dfm-name>"
        )

    model_dir = pathlib.Path(sys.argv[1]).resolve()
    model_prefix = sys.argv[2]
    expected_iteration = int(sys.argv[3])
    expected_dfm_name = sys.argv[4]
    dfm_path = model_dir / expected_dfm_name

    result = {
        "schema_version": 1,
        "status": "blocked_not_started",
        "model_dir": str(model_dir),
        "model_prefix": model_prefix,
        "expected_iteration": expected_iteration,
        "actual_iteration": None,
        "expected_dfm_name": expected_dfm_name,
        "dfm_path": str(dfm_path),
        "dfm_count": 0,
        "dfm_size_bytes": 0,
        "dfm_sha256": None,
        "onnx_version": None,
        "producer_name": None,
        "producer_version": None,
        "graph_name": None,
        "graph_node_count": 0,
        "initializer_count": 0,
        "opset_versions": [],
        "input_names": [],
        "output_names": [],
        "onnx_checker_passed": False,
        "errors": [],
        "safety": {
            "tensorflow_imported": False,
            "deepfacelab_main_executed": False,
            "checkpoint_files_modified": False,
            "dfm_file_modified": False,
        },
    }

    try:
        if not model_dir.is_dir():
            raise RuntimeError("Staging model directory does not exist: %s" % model_dir)

        dfm_files = sorted(
            [path for path in model_dir.iterdir() if path.is_file() and path.suffix.lower() == ".dfm"],
            key=lambda path: path.name.lower(),
        )
        result["dfm_count"] = len(dfm_files)

        if len(dfm_files) != 1:
            result["errors"].append(
                {
                    "type": "unexpected_dfm_count",
                    "expected": 1,
                    "actual": len(dfm_files),
                    "files": [path.name for path in dfm_files],
                }
            )
        if not dfm_path.is_file():
            result["errors"].append(
                {
                    "type": "expected_dfm_missing",
                    "expected_name": expected_dfm_name,
                }
            )

        iteration = load_model_iteration(model_dir, model_prefix)
        result["actual_iteration"] = iteration
        if iteration != expected_iteration:
            result["errors"].append(
                {
                    "type": "unexpected_model_iteration",
                    "expected": expected_iteration,
                    "actual": iteration,
                }
            )

        if dfm_path.is_file():
            size_bytes = int(dfm_path.stat().st_size)
            result["dfm_size_bytes"] = size_bytes
            result["dfm_sha256"] = sha256_file(dfm_path)
            if size_bytes <= 1024:
                result["errors"].append(
                    {
                        "type": "dfm_too_small",
                        "size_bytes": size_bytes,
                        "minimum_exclusive": 1024,
                    }
                )

            import onnx

            result["onnx_version"] = getattr(onnx, "__version__", None)
            model_proto = onnx.load(str(dfm_path))
            onnx.checker.check_model(model_proto)
            result["onnx_checker_passed"] = True

            graph = model_proto.graph
            result["producer_name"] = model_proto.producer_name
            result["producer_version"] = model_proto.producer_version
            result["graph_name"] = graph.name
            result["graph_node_count"] = len(graph.node)
            result["initializer_count"] = len(graph.initializer)
            result["opset_versions"] = [
                int(item.version) for item in model_proto.opset_import
            ]

            initializer_names = {item.name for item in graph.initializer}
            input_names = [
                normalize_tensor_name(item.name)
                for item in graph.input
                if item.name not in initializer_names
            ]
            output_names = [normalize_tensor_name(item.name) for item in graph.output]
            result["input_names"] = input_names
            result["output_names"] = output_names

            if not EXPECTED_INPUTS.issubset(set(input_names)):
                result["errors"].append(
                    {
                        "type": "missing_expected_inputs",
                        "expected": sorted(EXPECTED_INPUTS),
                        "actual": input_names,
                    }
                )
            if not EXPECTED_OUTPUTS.issubset(set(output_names)):
                result["errors"].append(
                    {
                        "type": "missing_expected_outputs",
                        "expected": sorted(EXPECTED_OUTPUTS),
                        "actual": output_names,
                    }
                )
            if 12 not in result["opset_versions"]:
                result["errors"].append(
                    {
                        "type": "unexpected_opset",
                        "expected_to_include": 12,
                        "actual": result["opset_versions"],
                    }
                )
            if result["graph_node_count"] <= 0:
                result["errors"].append({"type": "empty_onnx_graph"})
            if result["initializer_count"] <= 0:
                result["errors"].append({"type": "no_onnx_initializers"})

        result["status"] = "passed" if not result["errors"] else "blocked_invalid_dfm"
    except BaseException as exc:
        result["status"] = "blocked_validator_exception"
        result["errors"].append(
            {
                "type": type(exc).__name__,
                "error": str(exc),
                "traceback": traceback.format_exc(),
            }
        )

    print(BEGIN)
    print(json.dumps(result, sort_keys=True))
    print(END)
    sys.stdout.flush()
    return 0 if result.get("status") == "passed" else 1


if __name__ == "__main__":
    sys.exit(main())

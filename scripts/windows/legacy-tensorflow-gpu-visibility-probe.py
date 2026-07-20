from __future__ import print_function

import json
import os
import sys
import traceback


def write_stage(path, stage, message):
    if not path:
        return
    payload = {
        "stage": stage,
        "message": message,
    }
    temp_path = path + ".tmp"
    with open(temp_path, "w") as handle:
        json.dump(payload, handle)
    try:
        os.replace(temp_path, path)
    except AttributeError:
        if os.path.exists(path):
            os.remove(path)
        os.rename(temp_path, path)


def safe_text(value):
    try:
        return str(value)
    except Exception:
        return repr(value)


def json_safe(value):
    if value is None or isinstance(value, (bool, int, float, str)):
        return value
    if isinstance(value, bytes):
        try:
            return value.decode("utf-8", "replace")
        except Exception:
            return repr(value)
    if isinstance(value, dict):
        return {safe_text(key): json_safe(item) for key, item in value.items()}
    if isinstance(value, (list, tuple, set)):
        return [json_safe(item) for item in value]
    return safe_text(value)


def device_record(device):
    return {
        "name": safe_text(getattr(device, "name", "")),
        "device_type": safe_text(getattr(device, "device_type", "")),
        "memory_limit": int(getattr(device, "memory_limit", 0) or 0),
        "physical_device_desc": safe_text(getattr(device, "physical_device_desc", "")),
    }


def physical_device_record(device, tensorflow_module):
    record = {
        "name": safe_text(getattr(device, "name", device)),
        "device_type": safe_text(getattr(device, "device_type", "GPU")),
    }
    try:
        details = tensorflow_module.config.experimental.get_device_details(device)
        record["details"] = json_safe(details)
    except Exception as exc:
        record["details_error"] = safe_text(exc)
    return record


def main():
    stage_path = sys.argv[1] if len(sys.argv) > 1 else ""
    result = {
        "schema_version": 1,
        "status": "blocked_not_started",
        "python": {
            "executable": sys.executable,
            "version": sys.version,
            "prefix": sys.prefix,
        },
        "environment": {
            "pythonhome": os.environ.get("PYTHONHOME"),
            "pythonpath": os.environ.get("PYTHONPATH"),
            "cuda_path": os.environ.get("CUDA_PATH"),
            "cuda_home": os.environ.get("CUDA_HOME"),
            "cudnn_path": os.environ.get("CUDNN_PATH"),
            "cuda_visible_devices": os.environ.get("CUDA_VISIBLE_DEVICES"),
            "tf_force_gpu_allow_growth": os.environ.get("TF_FORCE_GPU_ALLOW_GROWTH"),
            "path": os.environ.get("PATH"),
        },
        "tensorflow_imported": False,
        "tensorflow": {},
        "physical_gpus": [],
        "local_devices": [],
        "gpu_device_name": "",
        "physical_gpu_count": 0,
        "local_gpu_count": 0,
        "gpu_visible": False,
        "errors": [],
        "safety": {
            "deepfacelab_main_imported": False,
            "deepfacelab_main_executed": False,
            "training_started": False,
            "tensor_operations_executed": False,
            "workspace_modified_intentionally": False,
        },
    }

    try:
        write_stage(stage_path, "tensorflow-import", "Importing TensorFlow only; DeepFaceLab main.py is not imported.")
        import tensorflow as tf

        result["tensorflow_imported"] = True
        result["tensorflow"]["version"] = safe_text(getattr(tf, "__version__", ""))
        result["tensorflow"]["module_file"] = safe_text(getattr(tf, "__file__", ""))

        try:
            result["tensorflow"]["built_with_cuda"] = bool(tf.test.is_built_with_cuda())
        except Exception as exc:
            result["tensorflow"]["built_with_cuda_error"] = safe_text(exc)

        try:
            build_info = tf.sysconfig.get_build_info()
            result["tensorflow"]["build_info"] = json_safe(build_info)
        except Exception as exc:
            result["tensorflow"]["build_info_error"] = safe_text(exc)

        write_stage(stage_path, "physical-gpu-enumeration", "Enumerating TensorFlow physical GPU devices without creating tensors.")
        physical_gpus = []
        try:
            if hasattr(tf.config, "list_physical_devices"):
                physical_gpus = list(tf.config.list_physical_devices("GPU"))
            else:
                physical_gpus = list(tf.config.experimental.list_physical_devices("GPU"))
        except Exception as exc:
            result["errors"].append({
                "stage": "physical_gpu_enumeration",
                "error": safe_text(exc),
                "traceback": traceback.format_exc(),
            })

        result["physical_gpus"] = [physical_device_record(item, tf) for item in physical_gpus]

        for device in physical_gpus:
            try:
                tf.config.experimental.set_memory_growth(device, True)
            except Exception as exc:
                result["errors"].append({
                    "stage": "set_memory_growth",
                    "device": safe_text(getattr(device, "name", device)),
                    "error": safe_text(exc),
                })

        write_stage(stage_path, "local-device-enumeration", "Enumerating TensorFlow local devices; no model or tensor workload is started.")
        try:
            from tensorflow.python.client import device_lib
            local_devices = list(device_lib.list_local_devices())
            result["local_devices"] = [device_record(item) for item in local_devices]
        except Exception as exc:
            result["errors"].append({
                "stage": "local_device_enumeration",
                "error": safe_text(exc),
                "traceback": traceback.format_exc(),
            })

        try:
            result["gpu_device_name"] = safe_text(tf.test.gpu_device_name())
        except Exception as exc:
            result["errors"].append({
                "stage": "gpu_device_name",
                "error": safe_text(exc),
                "traceback": traceback.format_exc(),
            })

        local_gpu_count = len([
            item for item in result["local_devices"]
            if safe_text(item.get("device_type", "")).upper() == "GPU"
        ])
        gpu_visible = bool(result["physical_gpus"] or local_gpu_count or result["gpu_device_name"])
        result["gpu_visible"] = gpu_visible
        result["physical_gpu_count"] = len(result["physical_gpus"])
        result["local_gpu_count"] = local_gpu_count
        result["status"] = "passed_gpu_visible" if gpu_visible else "blocked_no_gpu_visible"
    except BaseException as exc:
        result["status"] = "blocked_tensorflow_import_or_initialization"
        result["errors"].append({
            "stage": "tensorflow_import_or_initialization",
            "error_type": type(exc).__name__,
            "error": safe_text(exc),
            "traceback": traceback.format_exc(),
        })
    finally:
        write_stage(stage_path, "result", "Writing the sentinel JSON result; no training or tensor workload was started.")
        print("__DFLNEXT_TF_GPU_JSON_BEGIN__")
        print(json.dumps(json_safe(result), sort_keys=True))
        print("__DFLNEXT_TF_GPU_JSON_END__")
        sys.stdout.flush()
        write_stage(stage_path, "complete", "The TensorFlow/GPU worker finished and emitted its sentinel JSON result.")

    return 0 if result.get("status") == "passed_gpu_visible" else 1


if __name__ == "__main__":
    sys.exit(main())

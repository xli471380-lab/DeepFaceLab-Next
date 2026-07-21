from __future__ import print_function

import hashlib
import json
import math
import pathlib
import pickle
import sys
import traceback

import cv2
import numpy as np


BEGIN = "__DFLNEXT_MERGE_VALIDATION_JSON_BEGIN__"
END = "__DFLNEXT_MERGE_VALIDATION_JSON_END__"
MEDIA_EXTENSIONS = {
    ".png",
    ".jpg",
    ".jpeg",
    ".bmp",
    ".webp",
    ".tif",
    ".tiff",
}


def sha256_file(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        while True:
            chunk = stream.read(1024 * 1024)
            if not chunk:
                break
            digest.update(chunk)
    return digest.hexdigest().upper()


def media_files(directory):
    return [
        path
        for path in sorted(directory.iterdir(), key=lambda item: item.name.lower())
        if path.is_file() and path.suffix.lower() in MEDIA_EXTENSIONS
    ]


def all_files(directory):
    return [
        path
        for path in sorted(directory.iterdir(), key=lambda item: item.name.lower())
        if path.is_file()
    ]


def load_image(path, flags):
    image = cv2.imread(str(path), flags)
    if image is None:
        raise RuntimeError("OpenCV could not read image: %s" % path)
    return image


def image_shape(image):
    if len(image.shape) == 2:
        return [int(image.shape[0]), int(image.shape[1]), 1]
    return [int(image.shape[0]), int(image.shape[1]), int(image.shape[2])]


def finite_number(value):
    try:
        return math.isfinite(float(value))
    except Exception:
        return False


def load_model_iteration(model_dir, model_prefix):
    data_path = model_dir / (model_prefix + "_data.dat")
    if not data_path.is_file() or data_path.stat().st_size <= 0:
        raise RuntimeError("Missing model data file: %s" % data_path)
    value = pickle.loads(data_path.read_bytes())
    if not isinstance(value, dict):
        raise RuntimeError("Model data is not a dictionary: %s" % data_path)
    return int(value.get("iter", -1))


def main():
    if len(sys.argv) != 8:
        raise SystemExit(
            "usage: validate-p0-merge-output.py "
            "<input-dir> <aligned-dir> <merged-dir> <mask-dir> "
            "<model-dir> <model-prefix> <expected-iteration>"
        )

    input_dir = pathlib.Path(sys.argv[1]).resolve()
    aligned_dir = pathlib.Path(sys.argv[2]).resolve()
    merged_dir = pathlib.Path(sys.argv[3]).resolve()
    mask_dir = pathlib.Path(sys.argv[4]).resolve()
    model_dir = pathlib.Path(sys.argv[5]).resolve()
    model_prefix = sys.argv[6]
    expected_iteration = int(sys.argv[7])

    result = {
        "schema_version": 1,
        "status": "blocked_not_started",
        "input_dir": str(input_dir),
        "aligned_dir": str(aligned_dir),
        "merged_dir": str(merged_dir),
        "mask_dir": str(mask_dir),
        "model_dir": str(model_dir),
        "model_prefix": model_prefix,
        "expected_iteration": expected_iteration,
        "actual_iteration": None,
        "input_count": 0,
        "aligned_count": 0,
        "merged_count": 0,
        "mask_count": 0,
        "changed_output_count": 0,
        "nonzero_mask_count": 0,
        "records": [],
        "errors": [],
        "safety": {
            "tensorflow_imported": False,
            "deepfacelab_main_executed": False,
            "checkpoint_files_modified": False,
            "output_files_modified": False,
        },
    }

    try:
        for label, directory in (
            ("input", input_dir),
            ("aligned", aligned_dir),
            ("merged", merged_dir),
            ("mask", mask_dir),
            ("model", model_dir),
        ):
            if not directory.is_dir():
                result["errors"].append(
                    {"type": "missing_directory", "label": label, "path": str(directory)}
                )

        if not result["errors"]:
            input_paths = media_files(input_dir)
            aligned_paths = media_files(aligned_dir)
            merged_paths = media_files(merged_dir)
            mask_paths = media_files(mask_dir)
            merged_all = all_files(merged_dir)
            mask_all = all_files(mask_dir)

            result["input_count"] = len(input_paths)
            result["aligned_count"] = len(aligned_paths)
            result["merged_count"] = len(merged_paths)
            result["mask_count"] = len(mask_paths)

            if not input_paths:
                result["errors"].append({"type": "no_input_images"})
            if len(aligned_paths) < len(input_paths):
                result["errors"].append(
                    {
                        "type": "insufficient_aligned_images",
                        "input_count": len(input_paths),
                        "aligned_count": len(aligned_paths),
                    }
                )

            expected_names = [path.stem + ".png" for path in input_paths]
            merged_names = [path.name for path in merged_paths]
            mask_names = [path.name for path in mask_paths]

            if merged_names != expected_names:
                result["errors"].append(
                    {
                        "type": "merged_file_set_mismatch",
                        "expected": expected_names,
                        "actual": merged_names,
                    }
                )
            if mask_names != expected_names:
                result["errors"].append(
                    {
                        "type": "mask_file_set_mismatch",
                        "expected": expected_names,
                        "actual": mask_names,
                    }
                )
            if [path.name for path in merged_all] != expected_names:
                result["errors"].append(
                    {
                        "type": "unexpected_non_image_or_extra_merged_files",
                        "actual": [path.name for path in merged_all],
                    }
                )
            if [path.name for path in mask_all] != expected_names:
                result["errors"].append(
                    {
                        "type": "unexpected_non_image_or_extra_mask_files",
                        "actual": [path.name for path in mask_all],
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

            merged_by_name = {path.name: path for path in merged_paths}
            mask_by_name = {path.name: path for path in mask_paths}
            changed_count = 0
            nonzero_mask_count = 0

            for input_path in input_paths:
                output_name = input_path.stem + ".png"
                merged_path = merged_by_name.get(output_name)
                mask_path = mask_by_name.get(output_name)
                if merged_path is None or mask_path is None:
                    continue

                input_image = load_image(input_path, cv2.IMREAD_COLOR)
                merged_image = load_image(merged_path, cv2.IMREAD_COLOR)
                mask_image = load_image(mask_path, cv2.IMREAD_UNCHANGED)

                input_shape = image_shape(input_image)
                merged_shape = image_shape(merged_image)
                mask_shape = image_shape(mask_image)

                if input_shape[:2] != merged_shape[:2]:
                    result["errors"].append(
                        {
                            "type": "merged_dimensions_mismatch",
                            "file": output_name,
                            "input_shape": input_shape,
                            "merged_shape": merged_shape,
                        }
                    )
                if input_shape[:2] != mask_shape[:2]:
                    result["errors"].append(
                        {
                            "type": "mask_dimensions_mismatch",
                            "file": output_name,
                            "input_shape": input_shape,
                            "mask_shape": mask_shape,
                        }
                    )

                if mask_image.ndim == 3:
                    mask_plane = mask_image[:, :, 0]
                else:
                    mask_plane = mask_image

                nonzero_pixels = int(np.count_nonzero(mask_plane))
                mask_max = int(np.max(mask_plane)) if mask_plane.size else 0
                if nonzero_pixels > 0 and mask_max > 0:
                    nonzero_mask_count += 1
                else:
                    result["errors"].append(
                        {"type": "empty_merge_mask", "file": output_name}
                    )

                input_sha = sha256_file(input_path)
                merged_sha = sha256_file(merged_path)
                mask_sha = sha256_file(mask_path)
                changed_from_input = input_sha != merged_sha
                if changed_from_input:
                    changed_count += 1

                mean_abs_difference = None
                if input_image.shape == merged_image.shape:
                    difference = np.abs(
                        input_image.astype(np.float32) - merged_image.astype(np.float32)
                    )
                    mean_abs_difference = float(np.mean(difference))
                    if not finite_number(mean_abs_difference):
                        result["errors"].append(
                            {"type": "non_finite_image_difference", "file": output_name}
                        )

                result["records"].append(
                    {
                        "input_name": input_path.name,
                        "output_name": output_name,
                        "input_sha256": input_sha,
                        "merged_sha256": merged_sha,
                        "mask_sha256": mask_sha,
                        "input_size_bytes": int(input_path.stat().st_size),
                        "merged_size_bytes": int(merged_path.stat().st_size),
                        "mask_size_bytes": int(mask_path.stat().st_size),
                        "input_shape": input_shape,
                        "merged_shape": merged_shape,
                        "mask_shape": mask_shape,
                        "mask_nonzero_pixels": nonzero_pixels,
                        "mask_max_value": mask_max,
                        "changed_from_input": changed_from_input,
                        "mean_absolute_pixel_difference": mean_abs_difference,
                    }
                )

            result["changed_output_count"] = changed_count
            result["nonzero_mask_count"] = nonzero_mask_count

            if input_paths and changed_count == 0:
                result["errors"].append({"type": "no_merged_output_changed"})
            if input_paths and nonzero_mask_count != len(input_paths):
                result["errors"].append(
                    {
                        "type": "not_all_masks_nonzero",
                        "expected": len(input_paths),
                        "actual": nonzero_mask_count,
                    }
                )

        result["status"] = "passed" if not result["errors"] else "blocked_invalid_merge"
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

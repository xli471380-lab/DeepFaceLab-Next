from __future__ import print_function

import argparse
import builtins
import os
import runpy
import sys
import traceback


def _system_exit_code(value):
    if value is None:
        return 0
    if isinstance(value, int):
        return value
    return 1


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--dfl-root", required=True)
    parser.add_argument("--main-py", required=True)
    parser.add_argument("--expected-timed-input-count", type=int, default=1)
    parser.add_argument("main_arguments", nargs=argparse.REMAINDER)
    args = parser.parse_args()

    dfl_root = os.path.abspath(args.dfl_root)
    main_py = os.path.abspath(args.main_py)
    main_arguments = list(args.main_arguments)
    if main_arguments and main_arguments[0] == "--":
        main_arguments = main_arguments[1:]

    if not os.path.isdir(dfl_root):
        raise RuntimeError("DeepFaceLab root does not exist: %s" % dfl_root)
    if not os.path.isfile(main_py):
        raise RuntimeError("DeepFaceLab main.py does not exist: %s" % main_py)
    if args.expected_timed_input_count < 0:
        raise RuntimeError("Expected timed input count cannot be negative.")

    unexpected_prompt_count = [0]
    timed_input_count = [0]
    original_input = builtins.input
    original_argv = list(sys.argv)
    original_cwd = os.getcwd()
    interact_object = None
    original_input_in_time = None

    def reject_prompt(prompt=""):
        unexpected_prompt_count[0] += 1
        raise RuntimeError(
            "Unexpected blocking DeepFaceLab prompt during deterministic resume: %s"
            % prompt
        )

    def deterministic_no(prompt, max_time_sec):
        timed_input_count[0] += 1
        sys.stdout.write(
            "%s [DFLNEXT deterministic timed response: no]\n" % prompt
        )
        sys.stdout.flush()
        return False

    exit_code = 0
    failure = None
    try:
        builtins.input = reject_prompt
        os.chdir(dfl_root)
        if dfl_root not in sys.path:
            sys.path.insert(0, dfl_root)

        from core.interact import interact as interact_object

        original_input_in_time = interact_object.input_in_time
        interact_object.input_in_time = deterministic_no
        sys.argv = [main_py] + main_arguments

        print("DFLNEXT deterministic resume driver: blocking prompts disabled.")
        print("DFLNEXT deterministic resume driver: timed override response is no.")
        sys.stdout.flush()

        try:
            runpy.run_path(main_py, run_name="__main__")
        except SystemExit as exc:
            exit_code = _system_exit_code(exc.code)
    except BaseException:
        failure = traceback.format_exc()
        exit_code = 97
    finally:
        if interact_object is not None and original_input_in_time is not None:
            interact_object.input_in_time = original_input_in_time
        builtins.input = original_input
        sys.argv = original_argv
        os.chdir(original_cwd)

    print(
        "DFLNEXT deterministic resume driver: unexpected prompts %d."
        % unexpected_prompt_count[0]
    )
    print(
        "DFLNEXT deterministic resume driver: timed responses %d/%d."
        % (timed_input_count[0], args.expected_timed_input_count)
    )
    sys.stdout.flush()

    if failure is not None:
        print(failure, file=sys.stderr)
    if unexpected_prompt_count[0] != 0:
        print(
            "DFLNEXT deterministic resume driver error: blocking prompt observed.",
            file=sys.stderr,
        )
        return 98
    if timed_input_count[0] != args.expected_timed_input_count:
        print(
            "DFLNEXT deterministic resume driver error: unexpected timed response count.",
            file=sys.stderr,
        )
        return 99
    return exit_code


if __name__ == "__main__":
    sys.exit(main())

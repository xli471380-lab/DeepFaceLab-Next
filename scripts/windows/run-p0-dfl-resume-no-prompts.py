from __future__ import print_function

import argparse
import builtins
import os
import runpy
import sys
import traceback


_UNEXPECTED_PROMPT_COUNT = 0
_TIMED_INPUT_COUNT = 0
_SKIP_PENDING_COUNT = 0
_ORIGINAL_TRAINER_THREAD = None


def _system_exit_code(value):
    if value is None:
        return 0
    if isinstance(value, int):
        return value
    return 1


def reject_prompt(prompt=""):
    global _UNEXPECTED_PROMPT_COUNT
    _UNEXPECTED_PROMPT_COUNT += 1
    raise RuntimeError(
        "Unexpected blocking DeepFaceLab prompt during deterministic resume: %s"
        % prompt
    )


def deterministic_no(self, prompt, max_time_sec):
    global _TIMED_INPUT_COUNT
    _TIMED_INPUT_COUNT += 1
    sys.stdout.write(
        "%s [DFLNEXT deterministic timed response: no]\n" % prompt
    )
    sys.stdout.flush()
    return False


def deterministic_skip_pending(self):
    global _SKIP_PENDING_COUNT
    _SKIP_PENDING_COUNT += 1
    sys.stdout.write(
        "DFLNEXT deterministic resume driver: skipped interactive stdin drain.\n"
    )
    sys.stdout.flush()
    return None


def guarded_trainer_thread(*args, **kwargs):
    global _ORIGINAL_TRAINER_THREAD
    try:
        return _ORIGINAL_TRAINER_THREAD(*args, **kwargs)
    finally:
        # Historical Trainer.main waits for this event before it can observe
        # the close message. Ensure initialization failures cannot deadlock the
        # parent process until the outer timeout.
        try:
            args[2].set()
        except BaseException:
            pass
        try:
            args[1].put({"op": "close"})
        except BaseException:
            pass


def main():
    global _UNEXPECTED_PROMPT_COUNT
    global _TIMED_INPUT_COUNT
    global _SKIP_PENDING_COUNT
    global _ORIGINAL_TRAINER_THREAD

    parser = argparse.ArgumentParser()
    parser.add_argument("--dfl-root", required=True)
    parser.add_argument("--main-py", required=True)
    parser.add_argument("--expected-timed-input-count", type=int, default=1)
    parser.add_argument("--self-test-only", action="store_true")
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

    _UNEXPECTED_PROMPT_COUNT = 0
    _TIMED_INPUT_COUNT = 0
    _SKIP_PENDING_COUNT = 0

    original_input = builtins.input
    original_argv = list(sys.argv)
    original_cwd = os.getcwd()
    interact_class = None
    original_input_in_time = None
    original_input_skip_pending = None
    trainer_module = None
    original_trainer_thread = None

    exit_code = 0
    failure = None
    try:
        os.chdir(dfl_root)
        if dfl_root not in sys.path:
            sys.path.insert(0, dfl_root)

        from core.interact import interact as interact_object
        from mainscripts import Trainer as trainer_module

        interact_class = type(interact_object)
        original_input_in_time = interact_class.input_in_time
        original_input_skip_pending = interact_class.input_skip_pending
        original_trainer_thread = trainer_module.trainerThread
        _ORIGINAL_TRAINER_THREAD = original_trainer_thread

        # Patch class methods, not singleton-instance attributes. Windows
        # multiprocessing pickles the interact singleton when
        # input_skip_pending starts a child process; storing a local function
        # on that singleton makes the object unpicklable.
        interact_class.input_in_time = deterministic_no
        interact_class.input_skip_pending = deterministic_skip_pending
        trainer_module.trainerThread = guarded_trainer_thread
        builtins.input = reject_prompt

        print("DFLNEXT deterministic resume driver v3: blocking prompts disabled.")
        print("DFLNEXT deterministic resume driver v3: timed override response is no.")
        print("DFLNEXT deterministic resume driver v3: interactive stdin drain disabled.")
        print("DFLNEXT deterministic resume driver v3: trainer init deadlock guard armed.")
        sys.stdout.flush()

        if args.self_test_only:
            interact_object.input_skip_pending()
            timed_result = interact_object.input_in_time("DFLNEXT self-test timed prompt", 0)
            if timed_result is not False:
                raise RuntimeError("Deterministic timed response self-test did not return False.")
            print("DFLNEXT deterministic resume driver v3 self-test: passed.")
            sys.stdout.flush()
        else:
            sys.argv = [main_py] + main_arguments
            try:
                runpy.run_path(main_py, run_name="__main__")
            except SystemExit as exc:
                exit_code = _system_exit_code(exc.code)
    except BaseException:
        failure = traceback.format_exc()
        exit_code = 97
    finally:
        if trainer_module is not None and original_trainer_thread is not None:
            trainer_module.trainerThread = original_trainer_thread
        if interact_class is not None and original_input_skip_pending is not None:
            interact_class.input_skip_pending = original_input_skip_pending
        if interact_class is not None and original_input_in_time is not None:
            interact_class.input_in_time = original_input_in_time
        builtins.input = original_input
        sys.argv = original_argv
        os.chdir(original_cwd)
        _ORIGINAL_TRAINER_THREAD = None

    print(
        "DFLNEXT deterministic resume driver v3: unexpected prompts %d."
        % _UNEXPECTED_PROMPT_COUNT
    )
    print(
        "DFLNEXT deterministic resume driver v3: timed responses %d/%d."
        % (_TIMED_INPUT_COUNT, args.expected_timed_input_count)
    )
    print(
        "DFLNEXT deterministic resume driver v3: stdin drains skipped %d."
        % _SKIP_PENDING_COUNT
    )
    sys.stdout.flush()

    if failure is not None:
        print(failure, file=sys.stderr)
    if _UNEXPECTED_PROMPT_COUNT != 0:
        print(
            "DFLNEXT deterministic resume driver v3 error: blocking prompt observed.",
            file=sys.stderr,
        )
        return 98
    if _TIMED_INPUT_COUNT != args.expected_timed_input_count:
        print(
            "DFLNEXT deterministic resume driver v3 error: unexpected timed response count.",
            file=sys.stderr,
        )
        return 99
    expected_skip_count = 1
    if _SKIP_PENDING_COUNT != expected_skip_count:
        print(
            "DFLNEXT deterministic resume driver v3 error: unexpected stdin drain count.",
            file=sys.stderr,
        )
        return 100
    return exit_code


if __name__ == "__main__":
    sys.exit(main())

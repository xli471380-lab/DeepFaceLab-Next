from __future__ import print_function

import argparse
import base64
import builtins
import json
import os
import runpy
import sys


def _decode_answers(encoded):
    try:
        raw = base64.b64decode(encoded.encode("ascii"))
        value = json.loads(raw.decode("utf-8"))
    except Exception as exc:
        raise RuntimeError("Unable to decode scripted answers: %s" % (exc,))

    if not isinstance(value, list):
        raise RuntimeError("Scripted answers must decode to a JSON list.")

    return [str(item) for item in value]


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
    parser.add_argument("--answers-b64", required=True)
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

    answers = _decode_answers(args.answers_b64)
    answer_index = [0]
    original_input = builtins.input
    original_argv = list(sys.argv)
    original_cwd = os.getcwd()

    def scripted_input(prompt=""):
        index = answer_index[0]
        if index >= len(answers):
            raise RuntimeError(
                "Unexpected DeepFaceLab prompt after %d scripted answers: %s"
                % (index, prompt)
            )

        answer = answers[index]
        answer_index[0] += 1
        sys.stdout.write("%s%s\n" % (prompt, answer))
        sys.stdout.flush()
        return answer

    exit_code = 0
    try:
        builtins.input = scripted_input
        os.chdir(dfl_root)
        if dfl_root not in sys.path:
            sys.path.insert(0, dfl_root)
        sys.argv = [main_py] + main_arguments

        print(
            "DFLNEXT scripted prompt driver: armed with %d answers."
            % len(answers)
        )
        sys.stdout.flush()

        try:
            runpy.run_path(main_py, run_name="__main__")
        except SystemExit as exc:
            exit_code = _system_exit_code(exc.code)
    finally:
        builtins.input = original_input
        sys.argv = original_argv
        os.chdir(original_cwd)

    consumed = answer_index[0]
    print(
        "DFLNEXT scripted prompt driver: consumed %d/%d answers."
        % (consumed, len(answers))
    )
    sys.stdout.flush()

    if consumed != len(answers):
        print(
            "DFLNEXT scripted prompt driver error: not all answers were consumed.",
            file=sys.stderr,
        )
        return 98

    return exit_code


if __name__ == "__main__":
    sys.exit(main())

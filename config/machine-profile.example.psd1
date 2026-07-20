@{
    # Copy this file into config/local/ and rename it for the machine and
    # runtime environment, for example:
    #   config/local/hp-a2000-system-py312.psd1
    #   config/local/rtx5880-legacy-dfl.psd1
    # Files below config/local/ are intentionally ignored by Git.

    SchemaVersion = 1

    # Stable labels used in report paths. Use only letters, numbers, dots,
    # underscores, and hyphens. Do not use a person's name.
    MachineId = 'example-machine'
    EnvironmentId = 'example-environment'

    # engineering: script and compatibility development
    # baseline: historical end-to-end P0 validation
    # performance: full training and benchmark runs
    Role = 'engineering'

    # Leave a value empty when that tool is intentionally supplied by a
    # portable DeepFaceLab bundle or is not installed for this environment.
    PythonExe = 'C:\Path\To\python.exe'
    FFmpegExe = ''
    NvccExe = ''

    # Free-form local note. It is written only to ignored local artifacts.
    Notes = 'Describe the purpose of this machine/environment combination.'
}

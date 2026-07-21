@{
    # Copy this file into config/local/ and rename it for the physical machine
    # and its independent local runtime environment, for example:
    #   config/local/hp-a2000-system-py312.psd1
    #   config/local/rtx5880-legacy-dfl.psd1
    # Files below config/local/ are intentionally ignored by Git.

    SchemaVersion = 2

    # Stable labels used in report paths. Use only letters, numbers, dots,
    # underscores, and hyphens. Do not use a person's name.
    MachineId = 'example-machine'
    EnvironmentId = 'example-environment'

    # Both computers are complete development nodes. This field labels the
    # current profile or validation purpose; it does not assign a permanent
    # responsibility to the physical computer.
    Role = 'full-development'

    # Leave a value empty when that tool is intentionally supplied by a
    # portable DeepFaceLab bundle or is not installed for this environment.
    PythonExe = 'C:\Path\To\python.exe'
    FFmpegExe = ''
    NvccExe = ''

    # Free-form local note. It is written only to ignored local artifacts.
    Notes = 'Independent local environment for the same shared development workflow.'
}

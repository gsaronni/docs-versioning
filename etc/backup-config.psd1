@{
    # Leave blank to default to <Documents>\2026 for whoever's Windows
    # account actually runs this — no username to know or hardcode.
    # Set a real path here only if you want something different.
    SourcePath          = 'C:\Users\<username>\Documents'

    LocalRepoPath       = 'C:\Backup\repo-local'

    # Leave blank to default to etc\restic-repo.key next to this config
    # (relative to wherever this project lives — also no username needed).
    PasswordFile        = ''

    ExternalDriveLabel = 'BackupDrive'
    ExternalRepoSubpath = 'ResticRepo'

    KeepDaily           = 10
    KeepWeekly          = 4
    KeepMonthly         = 6
}
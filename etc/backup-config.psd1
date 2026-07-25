@{
    # EDIT THIS before first run — replace with dad's actual Windows username
    SourcePath          = 'C:\Users\REPLACE_ME\Documents\2026'

    LocalRepoPath       = 'C:\Backup\repo-local'
    PasswordFile        = 'C:\Backup\etc\restic-repo.key'

    # Dad labels the external drive itself once (right-click drive in
    # Explorer > Rename) — the script finds it by label, not drive letter,
    # since drive letters aren't guaranteed stable across reconnects.
    ExternalDriveLabel  = 'ExternalDisk'
    ExternalRepoSubpath = 'ResticRepo'

    KeepDaily           = 10
    KeepWeekly          = 4
    KeepMonthly         = 6

    LogRetentionDays    = 120
}

@{
    # EDIT THIS before first run — replace with dad's actual Windows username
    SourcePath          = "C:\Users\user\AppData\Local\Larian Studios\Baldur's Gate 3\PlayerProfiles\Public\Savegames"

    LocalRepoPath       = 'D:\bck\repo-local'
    PasswordFile        = 'D:\docs-versioning\etc\restic-repo.key'

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

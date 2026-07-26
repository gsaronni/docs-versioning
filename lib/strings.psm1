# lib/strings.psm1
# Single source of truth for every string a human actually sees.
# Language follows the existing $env:BACKUP_HELPER_TEST_MODE switch:
# -Test = English (dev/debugging), standard = Italian Dantesco (dad's build).

$script:Strings = @{

en = @{
    # --- window chrome ---
    Title            = "Backup Helper"
    BtnBackup        = "Back Up Now"
    BtnRestore       = "Restore Latest Backup"
    BtnFind          = "Find an Old File"
    BtnStop          = "Stop"
    BtnUpdate        = "Update"
    StatusReady      = "Ready"
    StatusStopped    = "Stopped"
    StatusFailed     = "Failed, see messages above"
    OpBackup         = "Backup"
    OpRestore        = "Restore"
    OpSearch         = "Search"
    OpUpdate         = "Update"
    BaseWorking      = "Working"
    BaseSearching    = "Searching"

    # --- find dialog ---
    FindPrompt       = "Type part of a file name (e.g. 'invoice' or 'march'):"
    FindTitle        = "Find an Old File"
    DlgOk            = "OK"
    DlgCancel        = "Cancel"

    # --- search results ---
    NothingToSearch  = "No backups are set up yet, nothing to search."
    NothingToSearchTitle = "Nothing to Search"
    NoMatches        = "No files found. Search again?"
    NoMatchesTitle   = "No Matches"
    GridTitle        = "Found {0} match(es), select one or more (Ctrl/Shift-click) to restore"

    # --- generic errors ---
    SomethingWrong   = "Something went wrong:`r`n`r`n{0}"
    ErrorTitle       = "Error"
    CallForHelp      = "Something went wrong. Please call for help rather than trying more things."

    # --- backup button ---
    CantBackupTitle  = "Can't Back Up Yet"
    ResticMissing    = "The backup tool (restic) isn't installed."
    SourceMissing    = "Source folder doesn't exist: {0}"
    DriveMissing     = "{0} isn't accessible."
    PasswordMissing  = "Password file not found: {0}"

    # --- restore button ---
    CantRestoreTitle = "Can't Restore Yet"
    ResticMissingCall = "The backup tool isn't installed. Please call for help."
    NoBackupsYet     = "No backups exist yet, nothing to restore."
    NotEnoughSpaceTitle = "Not Enough Space"
    NotEnoughSpace   = "Not enough disk space to restore.`r`n`r`nNeeded (approx): {0} GB`r`nAvailable: {1} GB`r`n`r`nFree up space and try again."

    # --- stop ---
    StopRequested    = "--- Stop requested, finishing current step... ---"
    Cleaned          = "Cleaned up partial restore files."
    OpStoppedByUser  = "--- {0} stopped by user ---"
    OpStarted        = "--- {0} started ---"
    OpCompleted      = "--- {0} completed ---"
    OpFailed         = "--- {0} FAILED, see errors above ---"
    SearchCompleted  = "--- Search completed ---"

    # --- backup-common: config / readiness ---
    ConfigNotFound   = "Config file not found: {0} (copy backup-config.template.psd1 to the right name and edit the paths)"

    # --- backup-common: backup flow ---
    CheckingLocalRepo  = "Checking local repo at {0}"
    LocalRepoNotFound  = "Local repo not found, initializing"
    LocalRepoInitOk    = "Local repo initialized"
    LocalRepoExists    = "Local repo already exists"
    AlreadyRanToday    = "Latest snapshot already dated today, nothing to back up. Checking external drive."
    StartingBackup     = "Starting backup of {0}"
    FilesAdded         = "Added {0} new, {1} changed file(s), {2} GiB added to the repository."
    SnapshotSaved      = "Snapshot {0} saved."
    BackupPartialWarn  = "WARNING: some source files could not be read, but the backup otherwise completed."
    BackupExitError    = "ERROR: backup exited with code {0}"
    BackupOk           = "Backup completed successfully"
    ApplyingRetention  = "Applying retention (keep-daily={0} keep-weekly={1} keep-monthly={2})"
    ResticNotFound     = "ERROR: restic not found in PATH."
    SourceMissingErr   = "ERROR: Source path does not exist: {0}"
    DriveMissingErr    = "ERROR: {0} is not accessible."
    PasswordMissingErr = "ERROR: Password file not found: {0}"
    RepoInitFailed     = "ERROR: restic init failed"

    # --- backup-common: external drive ---
    ExtDriveSkip       = "External drive ({0}) not connected, skipping, will retry next run"
    ExtDriveFound      = "External drive detected at {0}"
    ExtRepoInit        = "External repo not found, initializing (matching chunker params to local repo)"
    ExtRepoInitFailed  = "ERROR: external repo init failed (see restic output above)"
    ExtRepoInitOk      = "External repo initialized"

    # --- backup-common: restore ---
    RestoringLatest    = "Restoring your most recent backup..."
    FilesRestored      = "Restored {0} file(s), {1} GiB."
    TimestampQuirk     = "(A harmless Windows permission quirk prevented updating one folder's timestamp, your files restored completely and correctly.)"
    RestoreDoneAt      = "Done! Your files are here: {0}"
    NoReposYet         = "ERROR: no backups exist yet, nothing to restore."

    # --- backup-common: search ---
    CheckingRepo       = "Checking {0} repo..."
    RepoNotFoundSkip   = "{0} repo not found, skipping."
    SearchingRepo      = "Searching {0} for '{1}'..."
    NoMatchesInRepo    = "No matches in {0}."
    FoundInRepo        = "Found {0} match(es) in {1}."
    RestoringFile      = "Restoring '{0}' from {1} ({2})..."
    FileDoneAt         = "Done! Your file is here: {0}"
    FileRestoreErr     = "ERROR: something went wrong restoring that file. Please call for help."

    # --- backup-common: update ---
    UpdateUnreachable  = "Unreachable, connect to Netbird and try again."
    UpdateForcing      = "Forcing local copy to match origin/main, any local changes will be discarded."
    UpdateFetchFailed  = "git fetch failed (exit {0})"
    UpdateResetFailed  = "git reset failed (exit {0})"
    ShortcutMissing    = "Shortcut missing, regenerating."
}

it = @{
    Title            = "Custode dei Documenti"
    BtnBackup        = "Poni in Salvo"
    BtnRestore       = "Ritorna l'Ultimo Salvato"
    BtnFind          = "Cerca Documento Perduto"
    BtnStop          = "Arresta"
    BtnUpdate        = "Rinnova"
    StatusReady      = "Pronto"
    StatusStopped    = "Arrestato"
    StatusFailed     = "Fallito, leggi sopra i messaggi"
    OpBackup         = "Salvataggio"
    OpRestore        = "Ritorno"
    OpSearch         = "Ricerca"
    OpUpdate         = "Rinnovamento"
    BaseWorking      = "Opera in corso"
    BaseSearching    = "Cercando"

    FindPrompt       = "Scrivi parte del nome (es. 'fattura' o 'marzo'):"
    FindTitle        = "Cerca Documento Perduto"
    DlgOk            = "Va bene"
    DlgCancel        = "Desisto"

    NothingToSearch  = "Nulla è ancor custodito, nulla v'è da cercare."
    NothingToSearchTitle = "Nulla da Cercare"
    NoMatches        = "Nulla si è trovato. Cerchiamo ancora?"
    NoMatchesTitle   = "Nessun Riscontro"
    GridTitle        = "Trovati {0} riscontro/i, scegli uno o più (Ctrl/Shift-click) per ritornarli"

    SomethingWrong   = "Qualcosa è andato storto:`r`n`r`n{0}"
    ErrorTitle       = "Errore"
    CallForHelp      = "Qui si smarrisce la retta via. Chiamate l'arcangelo, non tentate altro da soli."

    CantBackupTitle  = "Non Ancora Possibile"
    ResticMissing    = "Lo strumento del salvataggio non è installato."
    SourceMissing    = "La cartella d'origine non esiste: {0}"
    DriveMissing     = "{0} non è raggiungibile."
    PasswordMissing  = "Chiave non trovata: {0}"

    CantRestoreTitle = "Non Ancora Possibile"
    ResticMissingCall = "Lo strumento non è installato. Chiamate l'arcangelo."
    NoBackupsYet     = "Nulla è ancor custodito, nulla v'è da ritornare."
    NotEnoughSpaceTitle = "Spazio Insufficiente"
    NotEnoughSpace   = "Spazio insufficiente per il ritorno.`r`n`r`nNecessario (circa): {0} GB`r`nDisponibile: {1} GB`r`n`r`nLiberate spazio e riprovate."

    StopRequested    = "--- Arresto richiesto, concludo il passo presente... ---"
    Cleaned          = "Rimossi i frammenti del ritorno interrotto."
    OpStoppedByUser  = "--- {0} arrestato per tua volontà ---"
    OpStarted        = "--- {0} ha inizio ---"
    OpCompleted      = "--- {0} è compiuto ---"
    OpFailed         = "--- {0} È FALLITO, leggi sopra gli errori ---"
    SearchCompleted  = "--- Ricerca è compiuta ---"

    ConfigNotFound   = "Chiave di configurazione non trovata: {0} (copia il modello e correggi i cammini)"

    CheckingLocalRepo  = "Verifico l'archivio locale in {0}"
    LocalRepoNotFound  = "L'archivio locale non esiste ancora, lo fondo ora"
    LocalRepoInitOk    = "L'archivio locale è fondato"
    LocalRepoExists    = "L'archivio locale già esiste"
    AlreadyRanToday    = "L'ultima memoria è già di oggi, nulla da salvare. Verifico l'unità esterna."
    StartingBackup     = "Inizio il salvataggio di {0}"
    FilesAdded         = "Aggiunti {0} nuovi, {1} mutati, {2} GiB posti nell'archivio."
    SnapshotSaved      = "Memoria {0} conservata."
    BackupPartialWarn  = "AVVISO: alcuni file non si poterono leggere, ma il salvataggio è comunque compiuto."
    BackupExitError    = "ERRORE: il salvataggio è fallito, codice {0}"
    BackupOk           = "Il salvataggio è compiuto"
    ApplyingRetention  = "Applico la regola della memoria (giorni={0} settimane={1} mesi={2})"
    ResticNotFound     = "ERRORE: lo strumento non si trova nel cammino."
    SourceMissingErr   = "ERRORE: la cartella d'origine non esiste: {0}"
    DriveMissingErr    = "ERRORE: {0} non è raggiungibile."
    PasswordMissingErr = "ERRORE: chiave non trovata: {0}"
    RepoInitFailed     = "ERRORE: la fondazione dell'archivio è fallita"

    ExtDriveSkip       = "Unità esterna ({0}) non connessa, la ritenterò al prossimo passo"
    ExtDriveFound      = "Unità esterna trovata in {0}"
    ExtRepoInit        = "Archivio esterno non trovato, lo fondo ora"
    ExtRepoInitFailed  = "ERRORE: la fondazione dell'archivio esterno è fallita"
    ExtRepoInitOk      = "L'archivio esterno è fondato"

    RestoringLatest    = "Discendo nell'archivio a ritrovar l'ultima tua memoria..."
    FilesRestored      = "Ritornati {0} file, {1} GiB."
    TimestampQuirk     = "(Un innocuo capriccio di Windows non poté mutar la data d'una cartella, i tuoi file son tornati integri e giusti.)"
    RestoreDoneAt      = "Fatto! I tuoi file riposano qui: {0}"
    NoReposYet         = "ERRORE: nulla è ancor custodito, nulla v'è da ritornare."

    CheckingRepo       = "Verifico l'archivio {0}..."
    RepoNotFoundSkip   = "Archivio {0} non trovato, proseguo."
    SearchingRepo      = "Cerco in {0} '{1}'..."
    NoMatchesInRepo    = "Nulla trovato in {0}."
    FoundInRepo        = "Trovati {0} riscontro/i in {1}."
    RestoringFile      = "Ritorno '{0}' del {1} ({2})..."
    FileDoneAt         = "Fatto! Il tuo file riposa qui: {0}"
    FileRestoreErr     = "ERRORE: qualcosa è andato storto. Chiamate l'arcangelo."

    UpdateUnreachable  = "Il cammino è chiuso, la rete non risponde. Ricongiungiti a Netbird e riprova."
    UpdateForcing      = "Riporto la copia locale a quella d'origine, ogni mutamento locale sarà perduto."
    UpdateFetchFailed  = "la ricerca dell'origine è fallita (codice {0})"
    UpdateResetFailed  = "il ritorno all'origine è fallito (codice {0})"
    ShortcutMissing    = "Il collegamento manca, lo rifondo."
}
}

function Get-Str {
    param(
        [Parameter(Mandatory)][string]$Key,
        [object[]]$FormatArgs
    )
    $lang = if ($env:BACKUP_HELPER_TEST_MODE -eq "1") { "en" } else { "it" }
    $template = $script:Strings[$lang][$Key]
    if ($null -eq $template) { return "[missing string: $Key]" }
    if ($FormatArgs -and $FormatArgs.Count -gt 0) { return ($template -f $FormatArgs) }
    return $template
}

Export-ModuleMember -Function Get-Str
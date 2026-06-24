; ---------------------------------------------------------------------------
; ekoloko custom NSIS installer logic
;
; electron-builder automatically !includes build/installer.nsh (it is the
; default value of the `nsis.include` option) and expands the macros below at
; the matching points in the generated installer script. `customInit` runs
; inside .onInit -- AFTER initMultiUser, BEFORE the install Section -- so it is
; the right place to clean up registry state the built-in install steps choke
; on.
;
; -- Problem 1: "Installation Aborted / Setup was not completed successfully" --
; electron-builder's built-in "remove the previous version" step
; (uninstallOldVersion, in installSection.nsh) reads the UninstallString from
; the registry and runs that old uninstaller. If it CANNOT launch it, or it
; returns a non-zero exit code, the step calls `Abort "Cannot uninstall"` and
; the whole install dies with a half-filled progress bar.
;
; This happens to any user whose uninstaller file is gone but whose registry
; entry survived: they deleted the install folder by hand, an AV/cleaner wiped
; it, or a previous install/uninstall was interrupted. The registry still
; advertises an uninstaller at a path that no longer exists, so every
; subsequent install aborts -- "it installed the first time and now it won't".
;
; Fix: at .onInit, detect a uninstall entry whose uninstaller .exe is missing
; and delete the dead keys. With no UninstallString left, uninstallOldVersion
; short-circuits (Goto Done) and the install proceeds as a clean reinstall into
; the same location. App DATA under %APPDATA%\ekoloko is never touched, so kids
; stay logged in and keep their progress.
;
; -- Problem 2: orphaned PER-MACHINE copy from older builds --
; An earlier build installed PER-MACHINE (C:\Program Files\ekoloko). The
; current build installs PER-USER (%LOCALAPPDATA%\Programs\ekoloko -> see
; "perMachine": false in package.json). Because the location changed,
; electron-builder's normal removal can't see the old copy, so users ended up
; with TWO ekoloko installs and the auto-updater only ever patched the per-user
; one. If that old per-machine copy is still present we offer to remove it; if
; only its dead registry entry remains we drop that too (otherwise, for a user
; with ONLY the per-machine entry, initMultiUser flips to all-users mode and
; uninstallOldVersion aborts on the missing per-machine uninstaller).
;
; Notes on registry layout (verified against app-builder-lib 22.x templates):
;   * InstallLocation is stored under ${INSTALL_REGISTRY_KEY} (Software\<GUID>),
;     NOT under the Uninstall key.
;   * The uninstaller is always "<InstallLocation>\Uninstall <ProductName>.exe".
;   * The uninstall-key GUID is identical across install modes; only the
;     hive/view differ. Old per-machine builds live under HKLM, and older NSIS
;     installers write under the 32-bit view (Wow6432Node), so HKLM is checked
;     in both views.
; ---------------------------------------------------------------------------

!define /ifndef EK_UNINSTALL_KEY "Software\Microsoft\Windows\CurrentVersion\Uninstall\${UNINSTALL_APP_KEY}"

!macro customInit
  Push $R8   ; old UninstallString
  Push $R9   ; old InstallLocation

  ; -- (1) Per-user (HKCU) stale entry: the direct cause of the abort. --------
  ; No elevation needed -- works in normal installs and silent auto-updates.
  ReadRegStr $R8 HKCU "${EK_UNINSTALL_KEY}" "UninstallString"
  ReadRegStr $R9 HKCU "${INSTALL_REGISTRY_KEY}" "InstallLocation"
  ${If} $R8 != ""
  ${AndIfNot} ${FileExists} "$R9\Uninstall ${PRODUCT_FILENAME}.exe"
    DetailPrint "ekoloko: clearing a stale per-user uninstall entry ($R9 is gone)."
    DeleteRegKey HKCU "${EK_UNINSTALL_KEY}"
    DeleteRegKey HKCU "${INSTALL_REGISTRY_KEY}"
  ${EndIf}

  ; -- (2) Per-machine (HKLM) copy / orphan, checked in both registry views. --
  SetRegView 32
  ReadRegStr $R8 HKLM "${EK_UNINSTALL_KEY}" "UninstallString"
  ReadRegStr $R9 HKLM "${INSTALL_REGISTRY_KEY}" "InstallLocation"
  ${If} $R8 == ""
    SetRegView 64
    ReadRegStr $R8 HKLM "${EK_UNINSTALL_KEY}" "UninstallString"
    ReadRegStr $R9 HKLM "${INSTALL_REGISTRY_KEY}" "InstallLocation"
  ${EndIf}
  ; (RegView now points at whichever view the entry was found in, so the
  ;  Delete/Exec below act on the correct view.)

  ${If} $R8 != ""
    ${If} ${FileExists} "$R9\Uninstall ${PRODUCT_FILENAME}.exe"
      ; Old per-machine copy still installed -- offer to remove it.
      ;   - Normal double-click install: the user is asked (default = Yes).
      ;   - Silent auto-update (/S): /SD IDYES answers Yes with no popup.
      ; Removing a Program Files copy needs admin, so a UAC prompt appears
      ; during a normal install; in a background auto-update no elevation is
      ; possible, so it's simply skipped that round and cleaned up next time.
      MessageBox MB_YESNO|MB_ICONQUESTION "An older copy of ekoloko was found on this computer (in Program Files).$\n$\nRemove it so you only have one copy? Your saved login and game progress will be kept." /SD IDYES IDNO ek_skip_old
        DetailPrint "Removing previous ekoloko installation in $R9 ..."
        ; Copy the old uninstaller into NSIS's auto-cleaned temp dir and run it
        ; pointed back at its real folder (_?=) so ExecWait actually BLOCKS until
        ; it finishes. (Run in place, an NSIS uninstaller self-copies to %TEMP%
        ; and returns immediately, which would race the install that follows.)
        CopyFiles /SILENT "$R9\Uninstall ${PRODUCT_FILENAME}.exe" "$PLUGINSDIR\ek-old-uninstall.exe"
        IfFileExists "$PLUGINSDIR\ek-old-uninstall.exe" 0 ek_fallback
          ExecWait '"$PLUGINSDIR\ek-old-uninstall.exe" /S _?=$R9'
          Delete "$PLUGINSDIR\ek-old-uninstall.exe"
          Goto ek_after_uninst
        ek_fallback:
          ; No uninstaller file at the expected path; run the registered
          ; uninstall command as-is as a best effort.
          ExecWait '$R8 /S'
        ek_after_uninst:
        ; _?= leaves the folder + uninstaller behind; clear the remainder.
        RMDir /r "$R9"
        DeleteRegKey HKLM "${EK_UNINSTALL_KEY}"
        DeleteRegKey HKLM "${INSTALL_REGISTRY_KEY}"
      ek_skip_old:
    ${Else}
      ; Dead per-machine entry (folder already gone). Drop it so a user who has
      ; ONLY this entry doesn't get flipped into all-users mode and aborted on
      ; a missing uninstaller. Needs admin to delete HKLM; best-effort if not.
      DetailPrint "ekoloko: clearing a stale per-machine uninstall entry ($R9 is gone)."
      DeleteRegKey HKLM "${EK_UNINSTALL_KEY}"
      DeleteRegKey HKLM "${INSTALL_REGISTRY_KEY}"
    ${EndIf}
  ${EndIf}
  SetRegView 64

  Pop $R9
  Pop $R8
!macroend

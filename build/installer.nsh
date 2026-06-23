; ---------------------------------------------------------------------------
; ekoloko custom NSIS installer logic
;
; electron-builder automatically !includes build/installer.nsh (it is the
; default value of the `nsis.include` option) and expands the macros below at
; the matching points in the generated installer script.
;
; Problem this solves: an earlier build installed PER-MACHINE
; (C:\Program Files\ekoloko). The current build installs PER-USER
; (%LOCALAPPDATA%\Programs\ekoloko -> see "perMachine": false in package.json).
; Because the install LOCATION changed, electron-builder's normal "remove the
; previous version" step can't see the old copy, so users ended up with TWO
; ekoloko installs running different versions -- the auto-updater only ever
; patched the per-user one. The support logs showed exactly this: the app
; launching from both C:\Program Files\ekoloko AND
; ...\AppData\Local\Programs\ekoloko, with the version flapping 1.0.10/1.0.11.
;
; On install we detect that orphaned per-machine copy and remove it:
;   - Normal double-click install: the user is asked (default = Yes).
;   - Silent auto-update (electron-updater runs setup with /S): the /SD IDYES
;     default answers Yes automatically, so it's cleaned up with no popup.
;
; App DATA (cache + saved login under %APPDATA%\ekoloko) is intentionally left
; untouched so children stay logged in and keep their game progress.
;
; Note: removing a Program Files copy needs admin rights, so a UAC prompt
; appears during a normal install. During a background auto-update no elevation
; is possible, so if the leftover is per-machine it's simply skipped that round
; (no worse than today) and cleaned up the next time the user runs a full
; installer.
; ---------------------------------------------------------------------------

!macro customInit
  Push $R8   ; old UninstallString
  Push $R9   ; old InstallLocation

  ; The uninstall-key GUID is identical across install modes (it is derived
  ; from appId); only the registry hive/view differ. The old per-machine build
  ; registered under HKLM. Older NSIS installers write under the 32-bit view
  ; (Wow6432Node), so check both views.
  SetRegView 32
  ReadRegStr $R8 HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${UNINSTALL_APP_KEY}" "UninstallString"
  ReadRegStr $R9 HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${UNINSTALL_APP_KEY}" "InstallLocation"
  ${If} $R8 == ""
    SetRegView 64
    ReadRegStr $R8 HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${UNINSTALL_APP_KEY}" "UninstallString"
    ReadRegStr $R9 HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${UNINSTALL_APP_KEY}" "InstallLocation"
  ${EndIf}
  SetRegView 64

  ${If} $R8 != ""
  ${AndIf} $R9 != ""
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
        ; No uninstaller file found at the expected path; run the registered
        ; uninstall command as-is as a best effort.
        ExecWait '$R8 /S'
      ek_after_uninst:
      ; _?= leaves the folder + uninstaller behind; clear the remainder.
      RMDir /r "$R9"
    ek_skip_old:
  ${EndIf}

  Pop $R9
  Pop $R8
!macroend

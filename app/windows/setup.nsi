Unicode true
ManifestDPIAware true
RequestExecutionLevel user
SetCompressor /SOLID zlib

!include "MUI2.nsh"
!include "LogicLib.nsh"
!define APP "WoB Model Viewer"
!define EXE "WoB Model Viewer.exe"
!define VERSION "1.5.3"
!define INSTALLER_SOURCE "${__FILEDIR__}"
!define UNINSTALL "Software\Microsoft\Windows\CurrentVersion\Uninstall\RIGELIO.WoBModelViewer"
!define CAP "Software\RIGELIO\WoBModelViewer\Capabilities"
!define OPEN_COMMAND '$\"$INSTDIR\${EXE}$\" -- $\"%1$\"'

Var ExistingLocation
Var ExistingVersion

!macro RequireViewerClosed LABEL
    check_${LABEL}:
    nsExec::ExecToStack /TIMEOUT=10000 `"$SYSDIR\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -NonInteractive -Command "if (Get-Process -Name 'WoB Model Viewer' -ErrorAction SilentlyContinue) { exit 10 }; exit 0"`
    Pop $0
    Pop $1
    StrCmp $0 "0" closed_${LABEL}
    IfSilent cancel_${LABEL}
    StrCmp $0 "10" running_${LABEL}
    MessageBox MB_RETRYCANCEL|MB_ICONEXCLAMATION "$(ViewerCheckFailed)" IDRETRY check_${LABEL}
    Goto cancel_${LABEL}
    running_${LABEL}:
    MessageBox MB_RETRYCANCEL|MB_ICONEXCLAMATION "$(ViewerRunning)" IDRETRY check_${LABEL}
    cancel_${LABEL}:
    SetErrorLevel 2
    Abort
    closed_${LABEL}:
!macroend

!macro RegisterType EXT ID DESCRIPTION
    WriteRegStr HKCU "Software\Classes\RIGELIO.WoBModelViewer.${ID}" "" "${DESCRIPTION}"
    WriteRegStr HKCU "Software\Classes\RIGELIO.WoBModelViewer.${ID}\DefaultIcon" "" '$\"$INSTDIR\${EXE}$\",0'
    WriteRegStr HKCU "Software\Classes\RIGELIO.WoBModelViewer.${ID}\shell\open\command" "" "${OPEN_COMMAND}"
    WriteRegStr HKCU "Software\Classes\${EXT}\OpenWithProgids" "RIGELIO.WoBModelViewer.${ID}" ""
    WriteRegStr HKCU "${CAP}\FileAssociations" "${EXT}" "RIGELIO.WoBModelViewer.${ID}"
!macroend

!macro UnregisterType EXT ID
    ReadRegStr $0 HKCU "Software\Classes\RIGELIO.WoBModelViewer.${ID}\shell\open\command" ""
    ${If} $0 == "${OPEN_COMMAND}"
        !if "${EXT}" == ".wobview"
            ReadRegStr $1 HKCU "Software\Classes\${EXT}" ""
            ${If} $1 == "RIGELIO.WoBModelViewer.View"
                DeleteRegValue HKCU "Software\Classes\${EXT}" ""
            ${EndIf}
        !endif
        DeleteRegKey HKCU "Software\Classes\RIGELIO.WoBModelViewer.${ID}"
        DeleteRegValue HKCU "Software\Classes\${EXT}\OpenWithProgids" "RIGELIO.WoBModelViewer.${ID}"
        DeleteRegValue HKCU "${CAP}\FileAssociations" "${EXT}"
    ${EndIf}
!macroend

Name "${APP}"
OutFile "${OUTPUT}"
InstallDir "$LOCALAPPDATA\Programs\WoB Model Viewer"
InstallDirRegKey HKCU "${UNINSTALL}" "InstallLocation"
VIProductVersion "${VERSION}.0"
VIAddVersionKey "ProductName" "${APP}"
VIAddVersionKey "FileDescription" "WoB Model Viewer Setup"
VIAddVersionKey "CompanyName" "RIGELIO Studio"
VIAddVersionKey "ProductVersion" "${VERSION}"
VIAddVersionKey "FileVersion" "${VERSION}"
VIAddVersionKey "LegalCopyright" "RIGELIO Studio"

!define MUI_ICON "${APP_ICON}"
!define MUI_UNICON "${APP_ICON}"
!define MUI_ABORTWARNING
!define MUI_FINISHPAGE_RUN "$INSTDIR\${EXE}"
!define MUI_FINISHPAGE_RUN_NOTCHECKED
!define MUI_FINISHPAGE_SHOWREADME
!define MUI_FINISHPAGE_SHOWREADME_TEXT "$(ChooseDefaults)"
!define MUI_FINISHPAGE_SHOWREADME_FUNCTION OpenDefaultApps
!define MUI_FINISHPAGE_SHOWREADME_NOTCHECKED
!define MUI_LICENSEPAGE_CHECKBOX
!define MUI_PAGE_CUSTOMFUNCTION_SHOW ShowExistingInstallation
!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_LICENSE "$(ViewerTerms)"
!define MUI_PAGE_CUSTOMFUNCTION_PRE SkipManagedDirectory
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_LANGUAGE "English"
!insertmacro MUI_LANGUAGE "Czech"
LicenseLangString ViewerTerms ${LANG_ENGLISH} "${INSTALLER_SOURCE}\Installer-Terms.en.txt"
LicenseLangString ViewerTerms ${LANG_CZECH} "${INSTALLER_SOURCE}\Installer-Terms.cs.txt"
LangString ViewerRunning ${LANG_ENGLISH} "Close all WoB Model Viewer windows, then click Retry."
LangString ViewerRunning ${LANG_CZECH} "Zavři všechna okna WoB Model Vieweru a klikni na Opakovat."
LangString ViewerCheckFailed ${LANG_ENGLISH} "Setup could not check if WoB Model Viewer is running. Click Retry or Cancel."
LangString ViewerCheckFailed ${LANG_CZECH} "Nepodařilo se ověřit, zda WoB Model Viewer běží. Zvol Opakovat nebo Storno."
LangString ViewerDataFailed ${LANG_ENGLISH} "Setup could not remove WoB Model Viewer settings or cache. Click Retry or Cancel."
LangString ViewerDataFailed ${LANG_CZECH} "Nepodařilo se odstranit nastavení nebo mezipaměť. Zvol Opakovat nebo Storno."
LangString ChooseDefaults ${LANG_ENGLISH} "Open default app settings"
LangString ChooseDefaults ${LANG_CZECH} "Otevřít výchozí aplikace"
LangString ExistingTitle ${LANG_ENGLISH} "WoB Model Viewer is already installed"
LangString ExistingTitle ${LANG_CZECH} "Viewer už je nainstalovaný"
LangString ExistingVersionUnknown ${LANG_ENGLISH} "unknown"
LangString ExistingVersionUnknown ${LANG_CZECH} "neznámá"
LangString ExistingUpdate ${LANG_ENGLISH} "Setup will update version $ExistingVersion to ${VERSION} in the existing folder.$\r$\n$\r$\n$ExistingLocation$\r$\n$\r$\nYour settings and saved files will be kept."
LangString ExistingUpdate ${LANG_CZECH} "Instalátor aktualizuje verzi $ExistingVersion na ${VERSION} ve stávající složce.$\r$\n$\r$\n$ExistingLocation$\r$\n$\r$\nNastavení a uložené soubory zůstanou k dispozici."
LangString ExistingReinstall ${LANG_ENGLISH} "Setup will reinstall version ${VERSION} in the existing folder.$\r$\n$\r$\n$ExistingLocation$\r$\n$\r$\nYour settings and saved files will be kept."
LangString ExistingReinstall ${LANG_CZECH} "Instalátor znovu nainstaluje verzi ${VERSION} do stávající složky.$\r$\n$\r$\n$ExistingLocation$\r$\n$\r$\nNastavení a uložené soubory zůstanou k dispozici."

Function .onInit
    ReadRegStr $0 HKCU "${UNINSTALL}" "InstallLocation"
    ${If} $0 != ""
        IfFileExists "$0\${EXE}" 0 fresh_install
        IfFileExists "$0\Uninstall.exe" 0 fresh_install
        StrCpy $ExistingLocation $0
        StrCpy $INSTDIR $ExistingLocation
        ReadRegStr $ExistingVersion HKCU "${UNINSTALL}" "DisplayVersion"
        ${If} $ExistingVersion == ""
            StrCpy $ExistingVersion "$(ExistingVersionUnknown)"
        ${EndIf}
    ${EndIf}
    fresh_install:
FunctionEnd

Function ShowExistingInstallation
    ${If} $ExistingLocation != ""
        ${NSD_SetText} $mui.WelcomePage.Title "$(ExistingTitle)"
        ${If} $ExistingVersion == "${VERSION}"
            ${NSD_SetText} $mui.WelcomePage.Text "$(ExistingReinstall)"
        ${Else}
            ${NSD_SetText} $mui.WelcomePage.Text "$(ExistingUpdate)"
        ${EndIf}
    ${EndIf}
FunctionEnd

Function SkipManagedDirectory
    ${If} $ExistingLocation != ""
        Abort
    ${EndIf}
FunctionEnd

Function OpenDefaultApps
    ExecShell "open" "ms-settings:defaultapps?registeredAppUser=WoB%20Model%20Viewer"
FunctionEnd

!cd "${PAYLOAD}"

Section "WoB Model Viewer"
    SetShellVarContext current
    !insertmacro RequireViewerClosed install
    SetOutPath "$INSTDIR"
    SetOverwrite on
    File "${EXE}"
    File "wob-gif.exe"
    File "Go-LICENSE.txt"
    File "README.en.md"
    File "README.cs.md"
    File "PRODUCTION-RESOURCES.json"
    File "Godot-LICENSE.txt"
    File "Godot-COPYRIGHT.txt"
    File "CormorantGaramond-OFL.txt"
    File "LICENSE"
    File "RESOURCE-LICENSES.md"
    WriteUninstaller "$INSTDIR\Uninstall.exe"
    CreateDirectory "$SMPROGRAMS\${APP}"
    CreateShortcut "$SMPROGRAMS\${APP}\${APP}.lnk" "$INSTDIR\${EXE}"
    CreateShortcut "$SMPROGRAMS\${APP}\Uninstall.lnk" "$INSTDIR\Uninstall.exe"
    WriteRegStr HKCU "${UNINSTALL}" "DisplayName" "${APP}"
    WriteRegStr HKCU "${UNINSTALL}" "UninstallString" '$\"$INSTDIR\Uninstall.exe$\"'
    WriteRegStr HKCU "${UNINSTALL}" "DisplayIcon" "$INSTDIR\${EXE}"
    WriteRegStr HKCU "${UNINSTALL}" "InstallLocation" "$INSTDIR"
    WriteRegStr HKCU "${UNINSTALL}" "DisplayVersion" "${VERSION}"
    WriteRegStr HKCU "${UNINSTALL}" "Publisher" "RIGELIO Studio"
    WriteRegDWORD HKCU "${UNINSTALL}" "NoModify" 1
    WriteRegDWORD HKCU "${UNINSTALL}" "NoRepair" 1
    !insertmacro RegisterType ".glb" "GLB" "glTF Binary Model"
    !insertmacro RegisterType ".gltf" "GLTF" "glTF Model"
    !insertmacro RegisterType ".fbx" "FBX" "FBX Model"
    !insertmacro RegisterType ".wobview" "View" "WoB Model Viewer View"
    ReadRegStr $0 HKCR ".wobview" ""
    ${If} $0 == ""
        WriteRegStr HKCU "Software\Classes\.wobview" "" "RIGELIO.WoBModelViewer.View"
    ${EndIf}
    WriteRegStr HKCU "${CAP}" "ApplicationName" "${APP}"
    WriteRegStr HKCU "${CAP}" "ApplicationDescription" "Offline GLB, glTF, FBX and saved view viewer"
    WriteRegStr HKCU "Software\RegisteredApplications" "${APP}" "${CAP}"
    System::Call "shell32::SHChangeNotify(i 0x08000000, i 0, p 0, p 0)"
SectionEnd

Section "Uninstall"
    SetShellVarContext current
    !insertmacro RequireViewerClosed uninstall
    InitPluginsDir
    SetOutPath "$PLUGINSDIR"
    File "${INSTALLER_SOURCE}\Remove-ViewerData.ps1"
    clean_retry:
    nsExec::ExecToStack /TIMEOUT=30000 `"$SYSDIR\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -NonInteractive -ExecutionPolicy RemoteSigned -File "$PLUGINSDIR\Remove-ViewerData.ps1"`
    Pop $0
    Pop $1
    StrCmp $0 "0" clean_done
    IfSilent clean_cancel
    MessageBox MB_RETRYCANCEL|MB_ICONEXCLAMATION "$(ViewerDataFailed)" IDRETRY clean_retry
    clean_cancel:
    SetErrorLevel 2
    Abort
    clean_done:
    Delete "$INSTDIR\${EXE}"
    Delete "$INSTDIR\wob-gif.exe"
    Delete "$INSTDIR\Go-LICENSE.txt"
    Delete "$INSTDIR\README.en.md"
    Delete "$INSTDIR\README.cs.md"
    Delete "$INSTDIR\PRODUCTION-RESOURCES.json"
    Delete "$INSTDIR\Godot-LICENSE.txt"
    Delete "$INSTDIR\Godot-COPYRIGHT.txt"
    Delete "$INSTDIR\CormorantGaramond-OFL.txt"
    Delete "$INSTDIR\LICENSE"
    Delete "$INSTDIR\RESOURCE-LICENSES.md"
    Delete "$INSTDIR\Uninstall.exe"
    RMDir "$INSTDIR"
    Delete "$SMPROGRAMS\${APP}\${APP}.lnk"
    Delete "$SMPROGRAMS\${APP}\Uninstall.lnk"
    RMDir "$SMPROGRAMS\${APP}"
    DeleteRegKey HKCU "${UNINSTALL}"
    !insertmacro UnregisterType ".glb" "GLB"
    !insertmacro UnregisterType ".gltf" "GLTF"
    !insertmacro UnregisterType ".fbx" "FBX"
    !insertmacro UnregisterType ".wobview" "View"
    EnumRegValue $0 HKCU "${CAP}\FileAssociations" 0
    ${If} $0 == ""
        DeleteRegKey HKCU "${CAP}"
        DeleteRegValue HKCU "Software\RegisteredApplications" "${APP}"
    ${EndIf}
    System::Call "shell32::SHChangeNotify(i 0x08000000, i 0, p 0, p 0)"
SectionEnd

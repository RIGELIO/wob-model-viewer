Unicode true
ManifestDPIAware true
RequestExecutionLevel user
SetCompressor /SOLID zlib

!include "MUI2.nsh"
!define APP "WoB Model Viewer"
!define EXE "WoB Model Viewer.exe"
!define UNINSTALL "Software\Microsoft\Windows\CurrentVersion\Uninstall\RIGELIO.WoBModelViewer"
!define PROG "RIGELIO.WoBModelViewer.GLB"
!define CAP "Software\RIGELIO\WoBModelViewer\Capabilities"

Name "${APP}"
OutFile "${OUTPUT}"
InstallDir "$LOCALAPPDATA\Programs\WoB Model Viewer"
InstallDirRegKey HKCU "${UNINSTALL}" "InstallLocation"
VIProductVersion "1.0.0.0"
VIAddVersionKey "ProductName" "${APP}"
VIAddVersionKey "FileDescription" "WoB Model Viewer Setup"
VIAddVersionKey "CompanyName" "RIGELIO Studio"
VIAddVersionKey "ProductVersion" "1.0.0"
VIAddVersionKey "FileVersion" "1.0.0"
VIAddVersionKey "LegalCopyright" "RIGELIO Studio"

!define MUI_ICON "${APP_ICON}"
!define MUI_UNICON "${APP_ICON}"
!define MUI_ABORTWARNING
!define MUI_FINISHPAGE_RUN "$INSTDIR\${EXE}"
!define MUI_FINISHPAGE_RUN_NOTCHECKED
!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_LANGUAGE "English"
!insertmacro MUI_LANGUAGE "Czech"

!cd "${PAYLOAD}"

Section "WoB Model Viewer"
    SetShellVarContext current
    SetOutPath "$INSTDIR"
    File "${EXE}"
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
    WriteRegStr HKCU "${UNINSTALL}" "DisplayVersion" "1.0.0"
    WriteRegStr HKCU "${UNINSTALL}" "Publisher" "RIGELIO Studio"
    WriteRegDWORD HKCU "${UNINSTALL}" "NoModify" 1
    WriteRegDWORD HKCU "${UNINSTALL}" "NoRepair" 1
    WriteRegStr HKCU "Software\Classes\${PROG}" "" "glTF Binary Model"
    WriteRegStr HKCU "Software\Classes\${PROG}\DefaultIcon" "" '$\"$INSTDIR\${EXE}$\",0'
    WriteRegStr HKCU "Software\Classes\${PROG}\shell\open\command" "" '$\"$INSTDIR\${EXE}$\" -- $\"%1$\"'
    WriteRegStr HKCU "Software\Classes\.glb\OpenWithProgids" "${PROG}" ""
    WriteRegStr HKCU "${CAP}" "ApplicationName" "${APP}"
    WriteRegStr HKCU "${CAP}" "ApplicationDescription" "Offline viewer for Wars of Bohemia GLB models"
    WriteRegStr HKCU "${CAP}\FileAssociations" ".glb" "${PROG}"
    WriteRegStr HKCU "Software\RegisteredApplications" "${APP}" "${CAP}"
    System::Call "shell32::SHChangeNotify(i 0x08000000, i 0, p 0, p 0)"
SectionEnd

Section "Uninstall"
    SetShellVarContext current
    Delete "$INSTDIR\${EXE}"
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
    ReadRegStr $0 HKCU "Software\Classes\${PROG}\shell\open\command" ""
    StrCmp $0 '$\"$INSTDIR\${EXE}$\" -- $\"%1$\"' 0 done
    DeleteRegKey HKCU "Software\Classes\${PROG}"
    DeleteRegValue HKCU "Software\Classes\.glb\OpenWithProgids" "${PROG}"
    DeleteRegKey HKCU "${CAP}"
    DeleteRegValue HKCU "Software\RegisteredApplications" "${APP}"
    System::Call "shell32::SHChangeNotify(i 0x08000000, i 0, p 0, p 0)"
    done:
SectionEnd

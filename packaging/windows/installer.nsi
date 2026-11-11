; TieSheet installer (NSIS).  Build with ./make-installer.sh, which passes the version in.
; Installs for the current user only (no admin needed), like the other tie* installers.
!ifndef VERSION
  !define VERSION "0.0"
!endif
!define APPNAME "TieSheet"
!define UNINSTKEY "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APPNAME}"

Name "${APPNAME} ${VERSION}"
OutFile "..\..\dist\tiesheet-setup.exe"
InstallDir "$LOCALAPPDATA\Programs\${APPNAME}"
RequestExecutionLevel user
Icon "..\..\assets\tiesheet.ico"
UninstallIcon "..\..\assets\tiesheet.ico"

Page directory
Page instfiles
UninstPage uninstConfirm
UninstPage instfiles

Section "Install"
  SetOutPath "$INSTDIR"
  File "..\..\build\win\tiesheet.exe"
  File "..\..\build\win\SDL2.dll"
  File "..\..\build\win\SDL2_ttf.dll"
  File "..\..\LICENSE"
  File "..\..\README.md"

  SetOutPath "$INSTDIR\fonts"
  File "..\..\fonts\LiberationMono-Regular.ttf"
  File "..\..\fonts\LiberationMono-Bold.ttf"
  File "..\..\fonts\LiberationMono-Italic.ttf"
  File "..\..\fonts\LiberationMono-BoldItalic.ttf"
  File "..\..\fonts\LICENSE-Liberation.txt"

  SetOutPath "$INSTDIR\licenses"
  File "..\..\assets\licenses\*.*"

  SetOutPath "$INSTDIR\examples"
  File "..\..\examples\budget.tsh"
  File "..\..\examples\schedule.csv"

  SetOutPath "$INSTDIR"
  CreateDirectory "$SMPROGRAMS\${APPNAME}"
  CreateShortcut "$SMPROGRAMS\${APPNAME}\${APPNAME}.lnk" "$INSTDIR\tiesheet.exe"
  CreateShortcut "$SMPROGRAMS\${APPNAME}\Uninstall.lnk" "$INSTDIR\uninstall.exe"

  WriteUninstaller "$INSTDIR\uninstall.exe"
  WriteRegStr HKCU "${UNINSTKEY}" "DisplayName" "${APPNAME}"
  WriteRegStr HKCU "${UNINSTKEY}" "DisplayVersion" "${VERSION}"
  WriteRegStr HKCU "${UNINSTKEY}" "DisplayIcon" "$INSTDIR\tiesheet.exe"
  WriteRegStr HKCU "${UNINSTKEY}" "InstallLocation" "$INSTDIR"
  WriteRegStr HKCU "${UNINSTKEY}" "UninstallString" '"$INSTDIR\uninstall.exe"'
  WriteRegDWORD HKCU "${UNINSTKEY}" "NoModify" 1
  WriteRegDWORD HKCU "${UNINSTKEY}" "NoRepair" 1
SectionEnd

Section "Uninstall"
  Delete "$INSTDIR\tiesheet.exe"
  Delete "$INSTDIR\SDL2.dll"
  Delete "$INSTDIR\SDL2_ttf.dll"
  Delete "$INSTDIR\LICENSE"
  Delete "$INSTDIR\README.md"
  Delete "$INSTDIR\fonts\LiberationMono-Regular.ttf"
  Delete "$INSTDIR\fonts\LiberationMono-Bold.ttf"
  Delete "$INSTDIR\fonts\LiberationMono-Italic.ttf"
  Delete "$INSTDIR\fonts\LiberationMono-BoldItalic.ttf"
  Delete "$INSTDIR\fonts\LICENSE-Liberation.txt"
  RMDir "$INSTDIR\fonts"
  Delete "$INSTDIR\licenses\*.*"
  RMDir "$INSTDIR\licenses"
  Delete "$INSTDIR\examples\budget.tsh"
  Delete "$INSTDIR\examples\schedule.csv"
  RMDir "$INSTDIR\examples"
  Delete "$INSTDIR\uninstall.exe"
  RMDir "$INSTDIR"

  Delete "$SMPROGRAMS\${APPNAME}\${APPNAME}.lnk"
  Delete "$SMPROGRAMS\${APPNAME}\Uninstall.lnk"
  RMDir "$SMPROGRAMS\${APPNAME}"

  DeleteRegKey HKCU "${UNINSTKEY}"
  ; the user's settings (%APPDATA%\tiesheet) and documents are left in place
SectionEnd

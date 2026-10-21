@echo off
chcp 65001 >nul
rem AltStore 갱신 문제 자동 진단. 결과는 .validation-tools\altstore-doctor\latest.txt 에도 저장된다.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\altstore_doctor.ps1" %*
echo.
pause

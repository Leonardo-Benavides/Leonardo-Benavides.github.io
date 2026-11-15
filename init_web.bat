@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0init_web.ps1" %*

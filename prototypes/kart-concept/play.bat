@echo off
rem PROTOTYPE - NOT FOR PRODUCTION
rem Question: Do drift-for-boost handling plus items make races feel skillful and chaotic?
rem Date: 2026-11-19
rem Double-click to play. Debug args go after a --:  play.bat -- --demo
start "" "C:\Godot\Godot_v4.8-beta3_win64.exe" --path "%~dp0." %*

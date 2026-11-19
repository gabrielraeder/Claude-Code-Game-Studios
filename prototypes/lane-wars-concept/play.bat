@echo off
rem PROTOTYPE - NOT FOR PRODUCTION
rem Question: Is building a tower maze in one lane fun and readable from an angled 3D camera?
rem Date: 2026-11-19
rem Double-click to play. Add --demo after a -- to start with a sample maze: play.bat -- --demo
start "" "C:\Godot\Godot_v4.8-beta3_win64.exe" --path "%~dp0." %*

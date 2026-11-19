@echo off
rem Dogworks Racing: Kennel Kingdom — double-click to play.
rem Debug args go after a --:  play.bat -- --autopilot
start "" "C:\Godot\Godot_v4.8-beta3_win64.exe" --path "%~dp0." %*

@echo off
rem PROTOTYPE - NOT FOR PRODUCTION
rem Question: Can 2+ PCs race smoothly over host/join with owner-authoritative karts?
rem Date: 2026-11-19
rem Joins a race. Type the host's IP (shown on the host's screen; a 100.x address for Tailscale).
set /p HOSTIP=Host IP:
start "" "C:\Godot\Godot_v4.8-beta3_win64.exe" --path "%~dp0." -- --join=%HOSTIP% %*

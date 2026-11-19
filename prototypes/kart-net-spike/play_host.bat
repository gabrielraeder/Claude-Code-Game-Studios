@echo off
rem PROTOTYPE - NOT FOR PRODUCTION
rem Question: Can 2+ PCs race smoothly over host/join with owner-authoritative karts?
rem Date: 2026-11-19
rem Hosts a race on UDP 24680 with 2 bots. Starts when a second player joins (or press Enter).
rem Windows may ask to allow Godot through the firewall: allow it on Private networks.
start "" "C:\Godot\Godot_v4.8-beta3_win64.exe" --path "%~dp0." -- --host --players=2 --bots=2 %*

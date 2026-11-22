@echo off
rem MSVC environment wrapper for tools/build_native.sh (bash cannot source vcvars64.bat).
rem Usage: build_native.bat <variant: debug|release|bench> [extra scons args]
rem Reads DOGWORKS_SH and DOGWORKS_FH from the environment (set by build_native.sh).
rem Env VSROOT overrides the Build Tools folder; JOBS sets the scons job count (default 8).
setlocal
set "HERE=%~dp0"
if "%VSROOT%"=="" set "VSROOT=C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools"
if "%JOBS%"=="" set "JOBS=8"
call "%VSROOT%\VC\Auxiliary\Build\vcvars64.bat" >nul
where cl.exe >nul
if errorlevel 1 (
  echo build_native.bat: cl.exe not on PATH after vcvars64.bat
  exit /b 1
)
set "VARIANT=%~1"
shift
cd /d "%HERE%..\native"
.venv\Scripts\scons.exe -j %JOBS% variant=%VARIANT% verbose=yes %1 %2 %3 %4 %5
exit /b %errorlevel%

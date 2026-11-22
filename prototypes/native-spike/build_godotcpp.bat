@echo off
rem PROTOTYPE - NOT FOR PRODUCTION. Usage: build_godotcpp.bat <template_debug|template_release>
call "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars64.bat" >nul
cd /d "%~dp0"
.venv\Scripts\scons.exe -f SConstruct platform=windows arch=x86_64 target=%1 gdextension_dir=out custom_api_file=out/extension_api.json %2 %3 %4

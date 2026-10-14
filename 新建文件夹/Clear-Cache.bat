@echo off
title Windows Cache Cleaner
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Clear-Cache.ps1"

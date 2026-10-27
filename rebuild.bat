@echo off
REM Rebuild the UPIShield database (Windows). Run from the project root.
REM If mysql is not on PATH, use the full path, e.g.
REM "C:\Program Files\MySQL\MySQL Server 8.0\bin\mysql.exe"
cd /d "%~dp0"
mysql --local-infile=1 -u root -p < sql\00_rebuild.sql
pause

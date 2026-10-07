@echo off
cd /d "%~dp0"
if not exist node_modules (
  call npm install
  if errorlevel 1 exit /b 1
)
if not exist .env.local (
  call npm run local:setup
  if errorlevel 1 exit /b 1
)
start "" http://localhost:4782/flutter/
npm run local:start

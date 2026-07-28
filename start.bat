@echo off
cd /d "%~dp0"
if not exist node_modules call npm install
start "" http://localhost:4782
npm start

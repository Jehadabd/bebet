@echo off
echo Cleaning build cache...
flutter clean
echo.
echo Building Windows release...
flutter build windows --release
pause

@echo off
title Edut Pro - Universite Privee Ar-Rahma (U.P.R) APK Builder

echo ===================================================================
echo   COMPILATION NOUVEAU APK (Universite Privee Ar-Rahma - U.P.R)
echo ===================================================================
echo.

cd /d "%~dp0"

set FLUTTER_EXE=flutter
if exist "C:\src\flutter\bin\flutter.bat" (
    set FLUTTER_EXE=C:\src\flutter\bin\flutter.bat
)

echo [1/4] Nettoyage du cache Flutter (Clean)...
call %FLUTTER_EXE% clean

echo.
echo [2/4] Installation des packages...
call %FLUTTER_EXE% pub get
if errorlevel 1 (
    echo Erreur lors de flutter pub get.
    pause
    exit /b 1
)

echo.
echo [3/4] Verification de l'environnement Android/Gradle...

echo.
echo [4/4] Compilation du fichier APK Release pour U P AR-RAHAMA...
call %FLUTTER_EXE% build apk --release --no-tree-shake-icons --dart-define=EDUT_WEB_API_BASE_URL=https://web-up-ar-rahama.vercel.app --dart-define=SUPABASE_URL=https://gyzyfctvmwsngicjlhrt.supabase.co --dart-define=SUPABASE_ANON_KEY=sb_publishable_K2JinfWif3_GLU6C6T5sDQ_JzofW6CU
if errorlevel 1 (
    echo.
    echo ===================================================================
    echo   ECHEC DE LA COMPILATION !
    echo   Veuillez verifier les messages d'erreur ci-dessus.
    echo ===================================================================
    pause
    exit /b 1
)

echo.
echo ===================================================================
echo   COMPILATION TERMINEE AVEC SUCCES !
echo   Fichier APK genere a :
echo   %~dp0build\app\outputs\flutter-apk\app-release.apk
echo ===================================================================
echo.
pause

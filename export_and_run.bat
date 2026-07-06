@echo off
echo ============================================================
echo   YOLO26m Waste Detection - Export Model Script
echo ============================================================
echo.

REM Check Python
python --version >nul 2>&1
if errorlevel 1 (
    echo [ERROR] Python tidak ditemukan. Install Python 3.8+ terlebih dahulu.
    pause
    exit /b 1
)

echo [1/3] Install ultralytics...
python -m pip install ultralytics --quiet

echo [2/3] Install tensorflow (untuk TFLite export)...
python -m pip install tensorflow --quiet

echo [3/3] Menjalankan export_model.py...
python mobile_waste_detection\scripts\export_model.py

echo.
echo ============================================================
echo  Setelah export berhasil, jalankan Flutter:
echo    cd mobile_waste_detection
echo    flutter pub get
echo    flutter run
echo ============================================================
pause

@echo off
setlocal EnableExtensions
cd /d "%~dp0"
title SmoothMotion fix28-qua2-lock test kit
echo SmoothMotion fix28-qua2-lock: hardware test kit (about 2 minutes)
echo Keep the test windows in the foreground and do not move them while they run.
echo.
rem Repository folder: take ..\bin\new.asi. Release package: Test\new.asi is already here.
if exist "..\bin\new.asi" copy /y "..\bin\new.asi" "new.asi" >nul
if not exist "new.asi" (
  echo Missing new.asi. Download the whole smoothmotion-locked folder, or extract the whole release ZIP.
  pause
  exit /b 1
)
if exist results rmdir /s /q results
mkdir results
if exist nvsmooth30.log del /q nvsmooth30.log
set SM86_PACING=locked
set SM86_DX12_TRANSFER=async
set SM86_TEST_NO_PROMPT=1

echo [1/6] Shader compile check with this PC's D3DCompiler
ShaderCheck.exe > results\1-shader-check.txt 2>&1
echo       exit code %ERRORLEVEL% (0 = PASS)

echo [2/6] DX12 transfer pixel test: staging, sync, async, async burst (no optical flow)
RTX20_TransferTest.exe > results\2-transfer-console.txt 2>&1
echo       exit code %ERRORLEVEL% (0 = PASS)
if exist rtx20-transfer-test-report.txt copy /y rtx20-transfer-test-report.txt results\2-transfer-report.txt >nul

echo [3/6] DX11 test, 20 s (10 s VSync, 10 s uncapped)
RTX20_SmokeTest.exe > results\3-dx11-console.txt 2>&1
echo       exit code %ERRORLEVEL% (0 = ran)
if exist rtx20-test-report.txt copy /y rtx20-test-report.txt results\3-dx11-report.txt >nul

echo [4/6] Older DX11 setup (blt model, 4x MSAA), 20 s
RTX20_SmokeTest.exe legacy > results\4-dx11-legacy-console.txt 2>&1
echo       exit code %ERRORLEVEL% (0 = ran)
if exist rtx20-legacy-test-report.txt copy /y rtx20-legacy-test-report.txt results\4-dx11-legacy-report.txt >nul

echo [5/6] DX12 test with resize and queue changes, about 25 s
RTX20_DX12_SmokeTest.exe > results\5-dx12-console.txt 2>&1
echo       exit code %ERRORLEVEL% (0 = PASS)
if exist rtx20-dx12-test-report.txt copy /y rtx20-dx12-test-report.txt results\5-dx12-report.txt >nul

echo [6/6] Vulkan test, 900 frames FIFO
RTX20_VulkanLayerTest.exe 900 fifo > results\6-vulkan-console.txt 2>&1
echo       exit code %ERRORLEVEL% (0 = PASS)

if exist nvsmooth30.log copy /y nvsmooth30.log results\nvsmooth30.log >nul
echo.
echo ===== On-screen pacing measured by the module (DXGI frame statistics) =====
findstr /c:"locked pacing" /c:"frame statistics unavailable" results\nvsmooth30.log > results\0-pacing-summary.txt
findstr /c:"Transfer mode" /c:"Pacing=locked" results\nvsmooth30.log >> results\0-pacing-summary.txt
type results\0-pacing-summary.txt
echo.
echo "0 repeated refresh(es)" and "even 2x" in every line = no stutter on the display.
echo Send the whole "results" folder back for review.
pause

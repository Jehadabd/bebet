# build_windows_release.ps1

$FIREBASE_LOCAL_PATH = "C:\Users\jihad\.gemini\firebase_cpp_sdk_windows"
$PDFIUM_LOCAL_PATH = "C:\Users\jihad\Downloads\pdfium-win-x64"

Write-Host "🚀 Starting Automated Windows Release Build..." -ForegroundColor Cyan

# 1. Clean (Optional - remove if you want faster builds)
# flutter clean

# 2. Get Dependencies
Write-Host "📦 Resolving dependencies..."
flutter pub get

# 3. Create Build Directory Structure
Write-Host "📁 Preparing build directories..."
$EXTRACTED_PATH = "build\windows\x64\extracted"
$PDFIUM_DL_PATH = "build\windows\x64\pdfium-download"

if (!(Test-Path $EXTRACTED_PATH)) { New-Item -Path $EXTRACTED_PATH -ItemType Directory -Force }
if (!(Test-Path $PDFIUM_DL_PATH)) { New-Item -Path $PDFIUM_DL_PATH -ItemType Directory -Force }

# 4. Copy SDKs
Write-Host "📂 Copying Firebase and Pdfium SDKs..."
if (Test-Path $FIREBASE_LOCAL_PATH) {
    Copy-Item -Path $FIREBASE_LOCAL_PATH -Destination "$EXTRACTED_PATH\firebase_cpp_sdk_windows" -Recurse -Force
} else {
    Write-Warning "Missing Firebase SDK at $FIREBASE_LOCAL_PATH"
}

if (Test-Path $PDFIUM_LOCAL_PATH) {
    Copy-Item -Path $PDFIUM_LOCAL_PATH -Destination "$PDFIUM_DL_PATH\pdfium-win-x64" -Recurse -Force
} else {
    Write-Warning "Missing Pdfium SDK at $PDFIUM_LOCAL_PATH"
}

# 5. Build
Write-Host "🛠️ Running Flutter Build Windows Release..." -ForegroundColor Green
flutter build windows --release

Write-Host "✅ Done! Your build folder is ready." -ForegroundColor Cyan

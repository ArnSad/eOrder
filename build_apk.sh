#!/usr/bin/env bash
# ==============================================================================
# Marg eOrder - Standalone Android APK Compilation Script
# ==============================================================================
set -e

echo "==> Cleaning previous Flutter build artifacts..."
flutter clean

echo "==> Resolving Flutter dependencies..."
flutter pub get

echo "==> Running verification tests..."
flutter test test/data_layer_test.dart

echo "==> Compiling Release Android APK..."
flutter build apk --release --split-per-abi

echo ""
echo "=============================================================================="
echo " BUILD SUCCESSFUL!"
echo " Universal Release APK: build/app/outputs/flutter-apk/app-release.apk"
echo " ARM64-v8a Device APK: build/app/outputs/flutter-apk/app-arm64-v8a-release.apk"
echo "=============================================================================="

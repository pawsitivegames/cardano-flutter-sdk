#!/bin/bash
# Script to copy the correct dylib based on SDK

# Use PODS_TARGET_SRCROOT if available (set by CocoaPods during build), otherwise use script directory
SCRIPT_DIR="${PODS_TARGET_SRCROOT:-.}"

FRAMEWORK_PATH="${SCRIPT_DIR}/Libs/cardano_flutter_rs.framework"
DEVICE_DYLIB="${SCRIPT_DIR}/Libs/cardano_flutter_rs_device.dylib"
SIMULATOR_DYLIB="${SCRIPT_DIR}/Libs/cardano_flutter_rs_simulator.dylib"
TARGET_DYLIB="${FRAMEWORK_PATH}/cardano_flutter_rs"

echo "[Cardano SDK] copy_dylib.sh: Script running from $SCRIPT_DIR"
echo "[Cardano SDK] copy_dylib.sh: PODS_TARGET_SRCROOT=$PODS_TARGET_SRCROOT"
echo "[Cardano SDK] copy_dylib.sh: EFFECTIVE_PLATFORM_NAME=$EFFECTIVE_PLATFORM_NAME"
echo "[Cardano SDK] copy_dylib.sh: Framework path: $FRAMEWORK_PATH"

if [[ "$EFFECTIVE_PLATFORM_NAME" == "-iphonesimulator" ]]; then
    echo "[Cardano SDK] copy_dylib.sh: Detected simulator build"
    if [ -f "$SIMULATOR_DYLIB" ]; then
        echo "[Cardano SDK] copy_dylib.sh: Copying simulator dylib to $TARGET_DYLIB"
        cp "$SIMULATOR_DYLIB" "$TARGET_DYLIB"
        echo "[Cardano SDK] copy_dylib.sh: Using simulator dylib"
    else
        echo "[Cardano SDK] copy_dylib.sh: ERROR - Simulator dylib not found at $SIMULATOR_DYLIB"
        exit 1
    fi
else
    echo "[Cardano SDK] copy_dylib.sh: Detected device build"
    if [ -f "$DEVICE_DYLIB" ]; then
        echo "[Cardano SDK] copy_dylib.sh: Copying device dylib to $TARGET_DYLIB"
        cp "$DEVICE_DYLIB" "$TARGET_DYLIB"
        echo "[Cardano SDK] copy_dylib.sh: Using device dylib"
    else
        echo "[Cardano SDK] copy_dylib.sh: ERROR - Device dylib not found at $DEVICE_DYLIB"
        exit 1
    fi
fi

# Fix install name so dyld finds the lib at @rpath/cardano_flutter_rs.framework/cardano_flutter_rs
# Runner's rpath includes @executable_path/Frameworks (set by CocoaPods)
echo "[Cardano SDK] copy_dylib.sh: Fixing install_name of dylib"
install_name_tool -id "@rpath/cardano_flutter_rs.framework/cardano_flutter_rs" "$TARGET_DYLIB" 2>/dev/null || true
echo "[Cardano SDK] copy_dylib.sh: Done"

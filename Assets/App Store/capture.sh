#!/bin/zsh
# Captures raw App Store screenshots into Raw/<device>/<language>/.
# Usage: ./capture.sh [languages...]   (defaults to en ja)
#        DEVICES=iPad ./capture.sh    (defaults to both iPhone and iPad)
#
# Each run installs the app fresh with location access granted, then the
# AppStoreScreenshots UI test sets the location, stages each screen and writes
# the captures. Run compose.swift afterwards to frame them.
set -e

SCRIPT_DIR=${0:A:h}
PROJECT_DIR=${SCRIPT_DIR:h:h}
PROJECT=$PROJECT_DIR/LiveSafe.xcodeproj
BUNDLE_ID=com.katagaki.LiveSafe
DERIVED_DATA=/tmp/livesafe-screenshots-dd
LANGUAGES=($@)
(( $# )) || LANGUAGES=(en ja)
typeset -A DEVICE_TYPES=(
  iPhone com.apple.CoreSimulator.SimDeviceType.iPhone-18-Pro-Max
  iPad com.apple.CoreSimulator.SimDeviceType.iPad-Pro-13-inch-M5-12GB
)
RUNTIME=$(xcrun simctl list runtimes available | grep -oE 'com\.apple\.CoreSimulator\.SimRuntime\.iOS-[0-9-]+' | tail -1)

# MARK: - Simulators

simulator() {
  local name="LiveSafe Screenshots $1" udid
  udid=$(xcrun simctl list devices available | grep "$name (" | head -1 | grep -oE '[0-9A-F-]{36}' || true)
  if [[ -z $udid ]]; then
    udid=$(xcrun simctl create "$name" $DEVICE_TYPES[$1] $RUNTIME)
  fi
  echo $udid
}

# The whole simulator is switched to the language and restarted, so the system's
# own text, such as the status bar's, matches the app's.
# The preferences are edited while it is shut down: a `defaults write` through
# simctl spawn does not survive the restart.
boot() {
  local locale=$([[ $2 == ja ]] && echo ja_JP || echo en_US)
  local preferences=~/Library/Developer/CoreSimulator/Devices/$1/data/Library/Preferences/.GlobalPreferences.plist
  # The first boot is what creates the preferences.
  xcrun simctl boot $1 2>/dev/null || true
  xcrun simctl bootstatus $1 -b >/dev/null
  xcrun simctl shutdown $1
  plutil -replace AppleLanguages -json "[\"$2\"]" "$preferences"
  plutil -replace AppleLocale -string $locale "$preferences"
  xcrun simctl boot $1
  xcrun simctl bootstatus $1 -b >/dev/null
  xcrun simctl status_bar $1 override --time 9:41 \
    --batteryState discharging --batteryLevel 31 \
    --dataNetwork 4g --cellularMode active --cellularBars 4 --operatorName ""
}

# MARK: - Build

# Schemes are not checked in, and the one Xcode makes for the app leaves the UI
# tests out, so the test target gets a scheme of its own.
SCHEME_DIR=$PROJECT/xcshareddata/xcschemes
mkdir -p $SCHEME_DIR
cat > $SCHEME_DIR/LiveSafeUITests.xcscheme <<'XML'
<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion = "2700" version = "1.7">
   <BuildAction parallelizeBuildables = "YES" buildImplicitDependencies = "YES">
      <BuildActionEntries>
         <BuildActionEntry buildForTesting = "YES" buildForRunning = "YES" buildForProfiling = "NO" buildForArchiving = "NO" buildForAnalyzing = "NO">
            <BuildableReference BuildableIdentifier = "primary" BlueprintIdentifier = "4F76DD562A33EAFFD6DB7A35" BuildableName = "LiveSafe.app" BlueprintName = "LiveSafe" ReferencedContainer = "container:LiveSafe.xcodeproj"></BuildableReference>
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction buildConfiguration = "Debug" selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv = "YES">
      <Testables>
         <TestableReference skipped = "NO">
            <BuildableReference BuildableIdentifier = "primary" BlueprintIdentifier = "5E2A7C9B3D1F4806B8A2C4E6" BuildableName = "LiveSafeUITests.xctest" BlueprintName = "LiveSafeUITests" ReferencedContainer = "container:LiveSafe.xcodeproj"></BuildableReference>
         </TestableReference>
      </Testables>
   </TestAction>
   <LaunchAction buildConfiguration = "Debug" selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB" launchStyle = "0" useCustomWorkingDirectory = "NO" ignoresPersistentStateOnLaunch = "NO" debugDocumentVersioning = "YES" debugServiceExtension = "internal" allowLocationSimulation = "YES">
      <BuildableProductRunnable runnableDebuggingMode = "0">
         <BuildableReference BuildableIdentifier = "primary" BlueprintIdentifier = "4F76DD562A33EAFFD6DB7A35" BuildableName = "LiveSafe.app" BlueprintName = "LiveSafe" ReferencedContainer = "container:LiveSafe.xcodeproj"></BuildableReference>
      </BuildableProductRunnable>
   </LaunchAction>
</Scheme>
XML

xcodebuild build-for-testing -project $PROJECT -scheme LiveSafeUITests \
  -destination "generic/platform=iOS Simulator" -derivedDataPath $DERIVED_DATA -quiet
APP=$DERIVED_DATA/Build/Products/Debug-iphonesimulator/LiveSafe.app
XCTESTRUN=$(ls $DERIVED_DATA/Build/Products/LiveSafeUITests_*.xctestrun | head -1)

# UI tests on a freshly booted simulator now and then miss a tap, so a failed run
# is given one more go. The test sets light and dark itself.
run_test() {
  run_test_once "$@" || run_test_once "$@"
}

# Prints only the assertion that failed, if any; -quiet would hide it.
run_test_once() {
  local log=$(mktemp) test_status=0
  TEST_RUNNER_SCREENSHOT_DIR=$3 TEST_RUNNER_SCREENSHOT_LANGUAGE=$2 \
    xcodebuild test-without-building -xctestrun $XCTESTRUN -destination "id=$1" \
    -only-testing:LiveSafeUITests/AppStoreScreenshots/testScreens \
    -test-timeouts-enabled YES -maximum-test-execution-time-allowance 1200 >$log 2>&1 || test_status=$?
  grep -E "error: -\[" $log || true
  rm -f $log
  return $test_status
}

# MARK: - Capture

# One language at a time on one device; the iPhone and iPad run side by side.
capture() {
  local device=$1 udid=$(simulator $1) language
  for language in $LANGUAGES; do
    raw_dir="$SCRIPT_DIR/Raw/$device/$language"
    mkdir -p "$raw_dir"
    boot $udid $language

    # A fresh install, so no layers, saved data or sheet position carry over.
    xcrun simctl terminate $udid $BUNDLE_ID 2>/dev/null || true
    xcrun simctl uninstall $udid $BUNDLE_ID 2>/dev/null || true
    xcrun simctl install $udid $APP
    xcrun simctl privacy $udid grant location $BUNDLE_ID

    run_test $udid $language "$raw_dir"
    echo "captured $device/$language"
  done
}

for device in ${=DEVICES:-iPhone iPad}; do
  capture $device &
done
wait

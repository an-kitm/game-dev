#!/bin/zsh
# Dev helper: sets the Android/Java env this machine needs, then runs flutter.
# Usage:
#   tool/dev.sh run -d emulator-5554      # build & run on an emulator
#   tool/dev.sh test                      # run unit tests
#   tool/dev.sh analyze
#   tool/dev.sh emulators --launch sequence_emu
export ANDROID_SDK_ROOT="$HOME/Library/Android/sdk"
export ANDROID_HOME="$HOME/Library/Android/sdk"
export JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home"
# Prefer Flutter's bundled Dart over the standalone brew dart-sdk.
export PATH="/opt/homebrew/share/flutter/bin:$PATH"

exec flutter "$@"

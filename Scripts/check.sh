#!/bin/zsh
# Use project-local caches without changing the selected system developer directory.
set -eu
cd "$(dirname "$0")/.."
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/module-cache"

check_developer_dir="$(xcode-select -p)"
if [[ "$check_developer_dir" == /Library/Developer/CommandLineTools ]]; then
    export SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.sdk
    swift build --disable-sandbox --cache-path .build/cache
    swift test --disable-sandbox --cache-path .build/cache --disable-xctest \
        -Xswiftc -load-plugin-library \
        -Xswiftc /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing/libTestingMacros.dylib
else
    swift build --cache-path .build/cache
    swift test --cache-path .build/cache --disable-xctest
fi
plutil -lint LocalMusic.xcodeproj/project.pbxproj
xmllint --noout LocalMusic.xcodeproj/xcshareddata/xcschemes/LocalMusic.xcscheme

#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
./build.sh
./scripts/test-signing.sh
TEST_DIR=$(mktemp -d "${TMPDIR:-/tmp}/sinaiprompt-native-tests.XXXXXX")
trap 'rm -rf "$TEST_DIR"' EXIT
xcrun clang -fobjc-arc -Wall -Wextra -Werror -framework Foundation -ISources Sources/SINDocument.m Sources/SINStore.m Sources/SINRecoveryWriter.m Tests/StoreTests.m -o "$TEST_DIR/store-tests"
"$TEST_DIR/store-tests"
xcrun clang -fobjc-arc -Wall -Wextra -Werror -framework Foundation -ISources Sources/SINDocument.m Sources/SINStore.m Sources/SINRecoveryWriter.m Tests/RecoveryTests.m -o "$TEST_DIR/recovery-tests"
"$TEST_DIR/recovery-tests"
xcrun clang -fobjc-arc -Wall -Wextra -Werror -framework Foundation -ISources Sources/SINDocument.m Sources/SINProjects.m Tests/ProjectTests.m -o "$TEST_DIR/project-tests"
"$TEST_DIR/project-tests"
xcrun clang -fobjc-arc -Wno-deprecated-declarations -framework AppKit -framework ImageIO -framework CoreGraphics -ISources Sources/SINNativeServices.m Sources/SINSliceExport.m Tests/native-services-tests.m -o "$TEST_DIR/service-tests"
"$TEST_DIR/service-tests"
xcrun clang -fobjc-arc -Wall -Wextra -Werror -framework AppKit -framework ImageIO -ISources Sources/SINSliceExport.m Tests/SliceExportTests.m -o "$TEST_DIR/slice-tests"
"$TEST_DIR/slice-tests"
xcrun clang -fobjc-arc -fmodules -DSIN_UNUSED_IMAGE_SCANNER_ONLY -framework Foundation -framework AppKit -framework WebKit -ISources Sources/SINDocument.m Sources/SINUnusedImages.m Tests/UnusedImageTests.m -o "$TEST_DIR/unused-tests"
"$TEST_DIR/unused-tests"
xcrun clang -fobjc-arc -framework JavaScriptCore scripts/check-js.m -o "$TEST_DIR/check-js"
"$TEST_DIR/check-js" Resources/Web/*.js
"build/Sin AI Prompt.app/Contents/MacOS/SinAIPrompt" --self-test
git diff --check

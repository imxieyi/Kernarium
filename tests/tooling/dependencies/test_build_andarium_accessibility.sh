#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
#
# The accessibility artifact's builder refuses an incomplete toolchain before
# it builds anything, and the packages it builds are the ones the LineageOS
# product stages and Andarium's ScreenReader recognises. It needs no prepared
# source, SDK or network: every refusal comes first.
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)
BUILDER="$ROOT_DIR/dependencies/build-andarium-accessibility.sh"
STAGER="$ROOT_DIR/android/lineage-24/tools/stage-accessibility-artifact.py"
SCREEN_READER="$ROOT_DIR/Andarium/AndariumCore/Sources/AndariumCore/ScreenReader.swift"
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/uml-andarium-accessibility.XXXXXX")
trap 'rm -rf -- "$TEST_ROOT"' EXIT HUP INT TERM

TEST_NAME=test-build-andarium-accessibility.sh
. "$(dirname -- "$0")/../support/expect.sh"

"$BUILDER" --help | grep -F -- "--archive-manifest" >/dev/null || fail "--help lacks the preparation"

# A stand-in toolchain: a JDK and an SDK with the pinned NDK and build-tools,
# none of which runs in these checks.
JDK="$TEST_ROOT/jdk"
mkdir -p "$JDK/bin"
printf '#!/bin/sh\nexit 1\n' >"$JDK/bin/java"
chmod +x "$JDK/bin/java"
SDK="$TEST_ROOT/sdk"
mkdir -p "$SDK/ndk/29.0.14206865" "$SDK/build-tools/36.1.0"

expect_diagnostic "unknown option" env JAVA_HOME="$JDK" ANDROID_HOME="$SDK" "$BUILDER" --gradle x
expect_diagnostic "JAVA_HOME must name a JDK" \
	env JAVA_HOME="$TEST_ROOT/no-jdk" ANDROID_HOME="$SDK" "$BUILDER"
expect_diagnostic "ANDROID_HOME must name an Android SDK" \
	env JAVA_HOME="$JDK" ANDROID_HOME="$TEST_ROOT/no-sdk" "$BUILDER"
mkdir -p "$TEST_ROOT/old-sdk/build-tools/36.1.0"
expect_diagnostic "the SDK has no NDK 29.0.14206865" \
	env JAVA_HOME="$JDK" ANDROID_HOME="$TEST_ROOT/old-sdk" "$BUILDER"
expect_diagnostic "the SDK has no build-tools" env JAVA_HOME="$JDK" ANDROID_HOME="$SDK" "$BUILDER"

# The packages the builder checks are those the stager requires, and
# TalkBack's is the one ScreenReader turns on and off.
for package in $(sed -n 's/^[A-Z_]*_PACKAGE=\(.*\)$/\1/p' "$BUILDER"); do
	grep -F "\"$package\"" "$STAGER" >/dev/null ||
		fail "the stager does not require $package, which the builder builds"
done
talkback=$(sed -n 's/^TALKBACK_PACKAGE=\(.*\)$/\1/p' "$BUILDER")
grep -F "\"$talkback/" "$SCREEN_READER" >/dev/null ||
	fail "ScreenReader does not recognise $talkback, which the builder builds"

printf '%s\n' "Andarium accessibility builder tests passed"

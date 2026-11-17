#!/bin/sh
set -eu
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

if [ -n "${SRCROOT:-}" ] && [ -f "$SRCROOT/README.md" ]; then
    README="$SRCROOT/README.md"
elif [ -n "${SRCROOT:-}" ] && [ -f "$SRCROOT/../README.md" ]; then
    README="$SRCROOT/../README.md"
elif [ -f "README.md" ]; then
    README="$(pwd)/README.md"
else
    SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
    README="$SCRIPT_DIR/../README.md"
fi

if [ ! -f "$README" ]; then
    echo "warning: README.md not found"
    exit 0
fi

PROJECT_ROOT=$(dirname "$README")
PROJECT_FILE=""

if [ -n "${PROJECT_FILE_PATH:-}" ] && [ -f "$PROJECT_ROOT/$PROJECT_FILE_PATH/project.pbxproj" ]; then
    PROJECT_FILE="$PROJECT_ROOT/$PROJECT_FILE_PATH/project.pbxproj"
elif [ -n "${PROJECT_DIR:-}" ] && [ -n "${PROJECT_FILE_PATH:-}" ] && [ -f "$PROJECT_DIR/$PROJECT_FILE_PATH/project.pbxproj" ]; then
    PROJECT_FILE="$PROJECT_DIR/$PROJECT_FILE_PATH/project.pbxproj"
else
    for PROJECT in "$PROJECT_ROOT"/*.xcodeproj; do
        if [ -f "$PROJECT/project.pbxproj" ]; then
            PROJECT_FILE="$PROJECT/project.pbxproj"
            break
        fi
    done
fi

read_build_setting() {
    SETTING_NAME="$1"

    if [ -n "$PROJECT_FILE" ] && [ -f "$PROJECT_FILE" ]; then
        /usr/bin/awk -v setting="$SETTING_NAME" '
            $0 ~ setting " = " {
                value = $0
                sub(".*" setting " = ", "", value)
                sub(";.*", "", value)
                print value
                exit
            }
        ' "$PROJECT_FILE"
    fi
}

VERSION="${MARKETING_VERSION:-$(read_build_setting MARKETING_VERSION)}"
BUILD="${CURRENT_PROJECT_VERSION:-$(read_build_setting CURRENT_PROJECT_VERSION)}"

UPDATED=$(date '+%d %B, %Y %H:%M:%S %Z')
if ! /usr/bin/perl -0pi -e "s/^Last Updated:.*/Last Updated: $UPDATED/m" "$README"; then
    echo "warning: unable to update README timestamp at $README"
    echo "warning: if this runs from Xcode, add README.md to the build phase Input Files and Output Files"
    exit 0
fi

if [ -n "$VERSION" ] && [ -n "$BUILD" ]; then
    if /usr/bin/grep -q '^Version:' "$README"; then
        /usr/bin/perl -0pi -e "s/^Version:.*$/Version: $VERSION , Build: $BUILD/m" "$README" || echo "warning: unable to update README version at $README"
    else
        /usr/bin/perl -0pi -e "s/^(Last Updated:.*)$/\$1\nVersion: $VERSION , Build: $BUILD/m" "$README" || echo "warning: unable to update README version at $README"
    fi
else
    echo "warning: version or build setting not found"
fi

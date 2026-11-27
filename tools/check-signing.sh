#!/bin/sh
# Build phase: keeps signing settings in Config/Local.xcconfig (git-ignored) and out of the project file.
#
# Fails if the project file sets a literal DEVELOPMENT_TEAM. Xcode writes one when a team is picked in
# Signing & Capabilities (which its own "requires a development team" error suggests when
# Config/Local.xcconfig is missing); a target-level value overrides the xcconfig files for everyone who
# builds the project, and the repository is public. SDK-conditional keys ("DEVELOPMENT_TEAM[sdk=...]") count too.
project="$PROJECT_FILE_PATH/project.pbxproj"
if grep -nE '"?DEVELOPMENT_TEAM(\[[^]]*\])?"? = ("[^"]+"|[^;" ]+);' "$project" >/dev/null; then
    echo "error: DEVELOPMENT_TEAM was written into Stop.xcodeproj, probably by picking a team in Signing & Capabilities. Discard that change to the project file (git checkout App/Stop.xcodeproj) and set DEVELOPMENT_TEAM in Config/Local.xcconfig instead (copy Config/Local.example.xcconfig)."
    exit 1
fi

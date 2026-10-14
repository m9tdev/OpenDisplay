#!/bin/sh
# Make build/appcast.xml, the Sparkle update feed, for build/OpenDisplay-VERSION.zip (the version in Info.plist).
# The release workflow attaches it to the GitHub release, and the app reads it from the latest release (SUFeedURL).
#
#   scripts/make-appcast.sh [NOTES_HTML]
#
# NOTES_HTML: a file with the release notes as HTML, which Sparkle shows in the update window.
# The zip is signed with the Sparkle EdDSA key: from SPARKLE_ED_PRIVATE_KEY (for example a GitHub secret), else
# from the login keychain (where Sparkle's generate_keys keeps it). DOWNLOAD_URL can replace the release URL of the
# zip, for a test feed.
set -eu
cd "$(dirname "$0")/.."

plist() { plutil -extract "$1" raw Resources/Info.plist; }
version="$(plist CFBundleShortVersionString)"
build="$(plist CFBundleVersion)"
minimum="$(plist LSMinimumSystemVersion)"
zip="build/OpenDisplay-$version.zip"
url="${DOWNLOAD_URL:-https://github.com/m9tdev/OpenDisplay/releases/download/v$version/OpenDisplay-$version.zip}"
sign_update=.build/artifacts/sparkle/Sparkle/bin/sign_update
[ -x "$sign_update" ] || swift package resolve > /dev/null

# sparkle:edSignature="…" length="…"
if [ -n "${SPARKLE_ED_PRIVATE_KEY:-}" ]; then
    key="$(mktemp)"
    trap 'rm -f "$key"' EXIT
    (umask 077 && printf '%s\n' "$SPARKLE_ED_PRIVATE_KEY" > "$key")
    signature="$("$sign_update" --ed-key-file "$key" "$zip")"
else
    signature="$("$sign_update" "$zip")"
fi

notes=""
if [ -n "${1:-}" ]; then
    notes="        <description><![CDATA[$(cat "$1")]]></description>"
fi

cat > build/appcast.xml <<EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
    <channel>
        <title>OpenDisplay</title>
        <item>
            <title>OpenDisplay $version</title>
            <pubDate>$(LC_ALL=C date -u "+%a, %d %b %Y %H:%M:%S +0000")</pubDate>
            <sparkle:version>$build</sparkle:version>
            <sparkle:shortVersionString>$version</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>$minimum</sparkle:minimumSystemVersion>
$notes
            <enclosure url="$url" type="application/octet-stream" $signature/>
        </item>
    </channel>
</rss>
EOF
echo "Made build/appcast.xml for $version (build $build)"

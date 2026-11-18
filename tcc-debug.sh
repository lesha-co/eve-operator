#!/usr/bin/env bash
#
# tl;dr: i've had messed up my permission database so i asked claude to debug it and
#        this what it spat out
#
# tcc-debug.sh — inspect why macOS thinks this app does/doesn't have a TCC permission.
#
# TCC does not key its records on "the app". It keys them on
#   (service, client bundle ID, csreq)
# where csreq is the *designated requirement* of the code signature that was
# present when the record was created. Two builds of the same bundle ID signed
# with different identities (Apple Development vs Developer ID) are two
# different clients as far as tccd is concerned, even though System Settings
# draws them as one row. This project avoids that by giving Debug its own
# bundle ID and its own display name, so the two never share a row.
#
# Usage:  ./tcc-debug.sh                 # both Debug and Release identities
#         ./tcc-debug.sh co.lesha.foo    # some other bundle ID
#         sudo ./tcc-debug.sh            # also reads the system TCC database

set -uo pipefail

if [[ $# -gt 0 ]]; then
  BUNDLE_IDS=("$@")
else
  BUNDLE_IDS=(co.lesha.eve-operator co.lesha.eve-operator.debug)
fi

# Substring used to fish related rows/paths out of TCC, LaunchServices and the
# log. Deliberately broader than the bundle IDs so stale variants (an old
# `-debug` suffix, a renamed product) still show up.
MATCH="${MATCH:-eve-operator}"
APP_MATCH="${APP_MATCH:-EVE Operator}"

hdr() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
note() { printf '\033[2m    %s\033[0m\n' "$*"; }

echo "Bundle IDs: ${BUNDLE_IDS[*]}"

# --- 1. Every copy of the app on this machine -------------------------------
hdr "Copies of the app on disk"
COPIES=$(
  {
    for id in "${BUNDLE_IDS[@]}"; do
      mdfind "kMDItemCFBundleIdentifier == '$id'" 2>/dev/null
    done
    ls -d "/Applications/$APP_MATCH"*.app 2>/dev/null
    ls -d "$HOME/Applications/$APP_MATCH"*.app 2>/dev/null
    ls -d "$HOME/Library/Developer/Xcode/DerivedData/"*/Build/Products/*/*.app 2>/dev/null
    ls -d "$HOME/.Trash/$APP_MATCH"*.app 2>/dev/null
    ls -d "$PWD/build/products/"*.app 2>/dev/null
  } | sort -u
)
if [[ -z "$COPIES" ]]; then
  note "none found (Spotlight does not index DerivedData or the Trash)"
else
  printf '%s\n' "$COPIES"
fi

# --- 2. Code identity of each copy ------------------------------------------
# Same bundle ID + different designated requirement = different TCC client.
hdr "Code signing identity per copy"
while IFS= read -r app; do
  [[ -n "$app" ]] || continue
  desc=$(codesign -dvv "$app" 2>&1)
  id=$(awk -F= '/^Identifier=/{print $2}' <<<"$desc")
  [[ "$id" == *"$MATCH"* ]] || continue
  echo
  echo "  $app"
  echo "    bundle id: $id"
  awk -F= '/^Authority=/{print "    authority: "$2; found=1; exit}
           END{if (!found) print "    authority: <unsigned or ad-hoc>"}' <<<"$desc"
  codesign -d -r- "$app" 2>&1 | sed -n 's/^designated => /    csreq:     /p'
done <<<"$COPIES"
note "two copies with the same bundle id but different csreq need separate grants"

# --- 3. What LaunchServices believes ----------------------------------------
# The Privacy pane resolves each TCC row to an app via LaunchServices. A record
# whose bundle ID resolves to nothing shows up as a stale/ghost row you cannot
# meaningfully toggle.
hdr "LaunchServices registrations"
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
"$LSREGISTER" -dump 2>/dev/null \
  | grep -E "^[[:space:]]*path:.*\.app" \
  | sed -E 's/^[[:space:]]*path:[[:space:]]*//; s/[[:space:]]*\(0x[0-9a-f]+\)$//' \
  | grep -iE "$MATCH|$APP_MATCH" \
  | sort -u \
  | while IFS= read -r p; do
      [[ -e "$p" ]] && echo "  $p" || echo "  $p   <-- MISSING ON DISK"
    done
note "MISSING entries and copies in ~/.Trash are what produce ghost rows;"
note "delete them, then: lsregister -kill -r -domain local -domain system -domain user"

# --- 4. The actual TCC records ----------------------------------------------
QUERY="select service, client, auth_value, auth_reason,
              datetime(last_modified,'unixepoch','localtime')
       from access where client like '%$MATCH%'
       order by client, service;"

hdr "TCC records (system database)"
if [[ $EUID -ne 0 ]]; then
  note "re-run with sudo to read /Library/Application Support/com.apple.TCC/TCC.db"
else
  sqlite3 "/Library/Application Support/com.apple.TCC/TCC.db" "$QUERY" 2>&1 | sed 's/^/  /'
  note "auth_value: 0=denied 2=allowed  |  one row per distinct csreq"
fi

hdr "TCC records (user database)"
sqlite3 "$HOME/Library/Application Support/com.apple.TCC/TCC.db" "$QUERY" 2>&1 | sed 's/^/  /'

# --- 5. What tccd has been saying -------------------------------------------
hdr "Recent tccd activity mentioning the app"
log show --last 1h --predicate 'subsystem == "com.apple.TCC"' --style compact 2>/dev/null \
  | grep -i "$MATCH" \
  | grep -iE "AUTHREQ_SUBJECT|denied|failed|Publishing|unable" \
  | tail -20 \
  | sed 's/^/  /'
note "'failed to find an Application URL for bundle ID' = ghost row in the Privacy pane"

# --- 6. How to start over ----------------------------------------------------
hdr "Reset"
for id in "${BUNDLE_IDS[@]}"; do
  echo "  tccutil reset ScreenCapture $id"
  echo "  tccutil reset Accessibility $id"
done
note "then relaunch the app — a Screen Recording grant never applies to the"
note "process that was running when it was given"

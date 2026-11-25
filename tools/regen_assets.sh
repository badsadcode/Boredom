#!/usr/bin/env bash
# Regenerate the generated assets from the Bad* generators.
#
#   BADLEVEL=~/BadLevel BADGUN=~/BadGun BADCHARS=~/BadCharacters tools/regen_assets.sh [level-seed]
#
# The level is a BadLevel "facility" (keycard sectors, lifts, stairs, secret door). A different
# seed gives a different facility; everything in the game reads it from the GLB, so just rerun.
set -euo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"
seed="${1:-13}"
: "${BADLEVEL:?set BADLEVEL to your BadLevel checkout}"
: "${BADGUN:?set BADGUN to your BadGun checkout}"
: "${BADCHARS:?set BADCHARS to your BadCharacters checkout}"

echo "== level (seed $seed)"
tmp="$(mktemp -d)"
( cd "$BADLEVEL" && python3 -m badlevel generate --seed "$seed" --recipe facility --formats glb,json --out "$tmp" )
cp "$tmp/badlevel_$seed.glb"  "$here/assets/level/facility.glb"
cp "$tmp/badlevel_$seed.json" "$here/assets/level/facility.json"

echo "== guns"
( cd "$BADGUN" && npm install --silent && npm run build --silent \
  && node dist/cli.js --archetype pistol  --style scrap  --seed 3 --out "$here/assets/guns" \
  && node dist/cli.js --archetype shotgun --style scrap  --seed 5 --out "$here/assets/guns" \
  && node dist/cli.js --archetype smg     --style modern --seed 2 --out "$here/assets/guns" )

echo "== characters"
( cd "$BADCHARS" && npm install --silent \
  && npm run -s cli -- export blocky worker 7  "$here/assets/chars" \
  && npm run -s cli -- export blocky zombie 9  "$here/assets/chars" \
  && npm run -s cli -- export stocky zombie 10 "$here/assets/chars" )

echo "done. Re-import with: godot --headless --path \"$here\" --import"

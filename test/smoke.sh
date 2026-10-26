#!/bin/sh
# Runs download.rb against test/fake_tumblr.rb inside the image, so it needs no
# credentials and no network:
#   docker run --rm --network none <image> test/smoke.sh
set -eu

app=$(cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

ruby -c "$app/download.rb"

# download.rb keeps its files next to itself, so run a copy to stay out of the volume.
cp "$app/download.rb" "$work/"
mkdir -p "$work/contents"
# Posts liked at or before this are already downloaded, so the old one is skipped.
echo 1650000000 > "$work/contents/.timestamp"

# The fake API refuses requests not signed with these.
export TUMBLR_CONSUMER_KEY=test-key TUMBLR_CONSUMER_SECRET=test-secret
export TUMBLR_CONSUMER_TOKEN=test-token TUMBLR_CONSUMER_TOKEN_SECRET=test-token-secret
BUNDLE_GEMFILE="$app/Gemfile" bundle exec ruby -r "$app/test/fake_tumblr.rb" "$work/download.rb"

failed=0
check() {
  file="$work/contents/2023/$1"
  if [ "$(cat "$file" 2>/dev/null)" = "/media/$2" ]; then
    echo "ok: $1"
  else
    echo "NG: $1 (expected the body of /media/$2)"
    failed=1
  fi
}
check 9998299999699-photo.jpg photo.jpg
check 9998299999699-caption.png caption.png
check 9998299999799-body.jpg body.jpg
check 9998299999799-vid1.jpg vid1.jpg
check 9998299999799-vid1.mp4 v.mp4
check 9998299999899-42.mp4 movie.mp4
check 9998299999899-42.jpg thumb.jpg

if [ -e "$work/contents/2020" ]; then
  echo "NG: a post older than .timestamp was downloaded"
  failed=1
fi
if [ "$(cat "$work/contents/.timestamp")" != 1700000300 ]; then
  echo "NG: .timestamp is $(cat "$work/contents/.timestamp"), expected 1700000300"
  failed=1
fi

exit $failed

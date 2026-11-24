#!/usr/bin/env bash
# Run one of this repo's Python scripts on ace, in a throwaway container from the polyis image.
#
#   ./run-on-ace.sh generate_data.py --dataset jnc0 --video te01.mp4 --frame-start 704 --overwrite
#   ./run-on-ace.sh scan_activity.py --datasets jnc0
#
# The container sees ace's shared tetris checkout, data and cache read-only (so it cannot touch the real cache),
# and this repo read-write at /demo. After generate_data.py succeeds, data/ is pulled back over the local data/.
# Override the defaults with DEMO_HOST, DEMO_REMOTE, TETRIS_CHECKOUT, DATA_ROOT and POLYIS_IMAGE.
set -euo pipefail

script=${1:?usage: ./run-on-ace.sh <script.py> [args...]}
shift
host=${DEMO_HOST:-ace}
remote=${DEMO_REMOTE:-/work/cwkt/projects/demo}
tetris=${TETRIS_CHECKOUT:-/work/cwkt/projects/tetris}
data=${DATA_ROOT:-/data/cwkt/data}
image=${POLYIS_IMAGE:-polyis-polyis}
cd "$(dirname "$0")"
[[ -f $script ]] || { echo "no such script: $script" >&2; exit 1; }

# Push the code; data/ stays as each side has it (generate_data.py refuses to overwrite it without --overwrite).
rsync -az --delete --exclude .git/ --exclude data/ --exclude __pycache__/ ./ "$host:$remote/"

# ace runs rootless Docker: container root is the remote user on the host, so files under $remote stay theirs.
ssh "$host" bash -s -- "$remote" "$tetris" "$data" "$image" "$script" "$@" <<'REMOTE'
set -euo pipefail
remote=$1 tetris=$2 data=$3 image=$4
shift 4
mkdir -p "$remote/data"
# A fixed name makes a second run fail at once while one is still going (a container outlives a dropped ssh).
docker run --rm --name "demo-${1%.py}" -w /polyis \
  -e POLYIS_DATA=/polyis-data -e POLYIS_CACHE=/polyis-cache -e TETRIS_ROOT=/polyis \
  -v "$tetris:/polyis:ro" -v "$remote:/demo" \
  -v "$data/polyis-data:/polyis-data:ro" -v "$data/polyis-cache:/polyis-cache:ro" \
  -v "$HOME/.gurobi/gurobi.lic:/opt/gurobi/gurobi.lic:ro" \
  "$image" python "/demo/$1" "${@:2}"
REMOTE

# Only generate_data.py produces data/; pulling after anything else could replace good local data with stale data.
if [[ $script == generate_data.py ]]; then
  rsync -az --delete "$host:$remote/data/" data/
fi

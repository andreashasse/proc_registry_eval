#!/usr/bin/env bash
# Runs every scenario against every registry and writes results/RESULTS.md.
#
#   ./run.sh              all registries
#   ./run.sh syn locker   only these
set -euo pipefail
cd "$(dirname "$0")"

if [ "$#" -gt 0 ]; then
    registries=("$@")
else
    registries=(global gproc syn horde locker highlander_pg)
fi

docker compose build
mkdir -p results

for registry in "${registries[@]}"; do
    echo
    echo "=== $registry"
    rm -f "results/$registry.result"
    # A fresh cluster per registry, so nothing carries over between them.
    REGISTRY="$registry" docker compose up -d node1 node2 node3
    REGISTRY="$registry" docker compose run --rm controller scenarios
    docker compose down
done

echo
echo "=== report"
docker compose run --rm controller report
docker compose down

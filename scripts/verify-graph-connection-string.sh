#!/usr/bin/env bash
#
# Guard against a regression of konnektr-io/charts#8.
#
# The `agedigitaltwins` (graph) chart used to always advertise the CloudNativePG
# read-only service (`<fullname>-ro`) as the second host of the API's Npgsql
# multi-host `Server=` list. That service selects `cnpg.io/instanceRole=replica`, so
# on a single-instance cluster it has NO endpoints, and on some CNIs the connection
# is silently dropped instead of refused — every new physical connection then waits
# for the Npgsql connect timeout and requests 504 behind a shorter gateway timeout.
#
# `helm lint` + `helm template` cannot see this: they only prove the chart renders.
# This script renders the chart in each relevant configuration and asserts on the
# connection string itself.
set -euo pipefail

CHART_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/graph"
failures=0

if [[ ! -d "$CHART_DIR/charts" ]]; then
  echo "FAIL: $CHART_DIR/charts is missing — run 'helm dependency update graph' first" >&2
  exit 1
fi

# servers [extra --set args...] -> prints the `Server=` list of the API connection string
servers() {
  local rendered line
  rendered="$(helm template test "$CHART_DIR" \
    --set api.enabled=true --set events.enabled=false "$@" 2>/dev/null)" || return 1
  line="$(printf '%s\n' "$rendered" \
    | grep -A1 -- '- name: ConnectionStrings__agedb' | tail -n1 || true)"
  [[ -n "$line" ]] || return 1
  line="${line#*Server=}"
  printf '%s' "${line%%;*}"
}

# expect <description> <expected Server= list> [extra --set args...]
expect() {
  local desc="$1" want="$2" got
  shift 2
  if ! got="$(servers "$@")"; then
    echo "FAIL: $desc — no api connection string rendered"
    failures=$((failures + 1))
  elif [[ "$got" != "$want" ]]; then
    echo "FAIL: $desc — Server=$got (want Server=$want)"
    failures=$((failures + 1))
  else
    echo "ok:   $desc — Server=$got"
  fi
}

expect "chart-managed cluster, 1 instance (no replicas -> no -ro)" \
  "test-graph-rw" \
  --set cluster.enabled=true --set cluster.cluster.instances=1

expect "chart-managed cluster, 3 instances (replicas -> -ro kept)" \
  "test-graph-rw,test-graph-ro" \
  --set cluster.enabled=true --set cluster.cluster.instances=3

expect "externally managed cluster (replica count unknown -> -ro kept)" \
  "test-graph-rw,test-graph-ro" \
  --set cluster.enabled=false

expect "readOnlyHost=true force-enables -ro on a single-instance cluster" \
  "test-graph-rw,test-graph-ro" \
  --set cluster.enabled=true --set cluster.cluster.instances=1 \
  --set api.database.readOnlyHost=true

expect "readOnlyHost=false drops -ro on a multi-instance cluster" \
  "test-graph-rw" \
  --set cluster.enabled=true --set cluster.cluster.instances=3 \
  --set api.database.readOnlyHost=false

# An unknown value must fail the render rather than silently guessing one of the two.
if helm template test "$CHART_DIR" --set api.enabled=true \
  --set api.database.readOnlyHost=maybe >/dev/null 2>&1; then
  echo "FAIL: an invalid api.database.readOnlyHost was accepted"
  failures=$((failures + 1))
else
  echo "ok:   invalid api.database.readOnlyHost fails the render"
fi

if ((failures > 0)); then
  echo "$failures graph connection-string check(s) FAILED"
  exit 1
fi
echo "all graph connection-string checks passed"

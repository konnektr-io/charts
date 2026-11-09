#!/usr/bin/env bash
#
# Guards konnektr-io/charts#2 — builtin support for the AGE image variants.
#
# `helm lint` + `helm template` only prove that the chart renders; they cannot see
# WHICH image the cluster ends up running nor WHICH SQL the database bootstraps
# with. This script renders the graph chart in every configuration the feature
# exposes and asserts on the rendered values:
#
#   1. the CNPG subchart's ImageCatalog is the image path — the Cluster carries an
#      `imageCatalogRef` with a major, and no `imageName`, so the default really
#      goes through the catalog instead of a pinned tag;
#   2. every catalog entry is a konnektr-io `age-pgvector*` image whose tag carries
#      the same major it is filed under (CloudNativePG trusts `major` blindly, so a
#      copy/paste slip would ship a PG16 image labelled 18), and no entry regresses
#      to the bare `age` image, which does not promise pgvector;
#   3. the bootstrap SQL still carries the whole AGE recipe and creates PostGIS
#      defensively, so the one list works on every image variant (a plain
#      `CREATE EXTENSION postgis` fails the bootstrap of the default image);
#   4. the documented variant switch (replacing `imageCatalog.images`) and the
#      documented escape hatch (`images: []` + `imageName`) both render;
#   5. contradictory values fail the render instead of being silently ignored:
#      `imageName` next to a catalog, the unused `version.major`/`version.age`
#      keys, a major with no catalog entry, and a configuration that would fall
#      back to the AGE-less upstream `<type>` image.
set -euo pipefail

CHART_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/graph"
RELEASE="test"
CATALOG="$RELEASE-cluster"
failures=0

if [[ ! -d "$CHART_DIR/charts" ]]; then
  echo "FAIL: $CHART_DIR/charts is missing — run 'helm dependency update graph' first" >&2
  exit 1
fi

ok() { echo "ok:   $1"; }
bad() {
  echo "FAIL: $1"
  failures=$((failures + 1))
}

# catalog_images [extra args...] -> "<major> <image>" for the rendered ImageCatalog
catalog_images() {
  helm template "$RELEASE" "$CHART_DIR" --set cluster.enabled=true "$@" \
    --show-only charts/cluster/templates/image-catalog.yaml 2>/dev/null |
    awk '
      /^    - image: / { gsub(/"/, "", $3); image = $3; next }
      /^      major: / { print $2, image }
    '
}

# cluster_spec [extra args...] -> the rendered Cluster manifest
cluster_spec() {
  helm template "$RELEASE" "$CHART_DIR" --set cluster.enabled=true --set api.enabled=false "$@" \
    --show-only charts/cluster/templates/cluster.yaml 2>/dev/null
}

echo "== image catalog is the image path"
spec="$(cluster_spec)"
if grep -q 'imageCatalogRef:' <<<"$spec" && grep -q "name: $CATALOG" <<<"$spec"; then
  ok "the Cluster runs from ImageCatalog/$CATALOG"
else
  bad "the Cluster does not reference ImageCatalog/$CATALOG"
fi
if grep -q '^    major: 18$' <<<"$spec"; then
  ok "imageCatalogRef.major comes from cluster.version.postgresql (18)"
else
  bad "imageCatalogRef.major is not 18 as cluster.version.postgresql says"
fi
if grep -q '^  imageName:' <<<"$spec"; then
  bad "a default install still renders imageName — the catalog would be dead weight"
else
  ok "no imageName in the default render (the catalog is the only image path)"
fi

rows="$(catalog_images)"
majors="$(printf '%s\n' "$rows" | awk '{ print $1 }' | sort -n | tr '\n' ' ')"
majors="${majors% }"
if [[ "$majors" != "16 17 18" ]]; then
  bad "default catalog majors: '$majors' (want '16 17 18')"
else
  ok "default catalog majors: $majors"
fi

mismatch="$(printf '%s\n' "$rows" | awk '
  {
    image = $2
    if (index(image, "ghcr.io/konnektr-io/age-pgvector") != 1) { print "not an age-pgvector* image: " image; next }
    tag = substr(image, index(image, ":") + 1)
    if (index(tag, $1 "-") != 1) { print "major " $1 " tagged " tag }
  }')"
if [[ -n "$mismatch" ]]; then
  bad "catalog entries do not match their variant/major:"
  printf '        %s\n' $mismatch
else
  ok "every catalog entry is an age-pgvector* image tagged with its own major"
fi
if printf '%s\n' "$rows" | grep -q 'konnektr-io/age:'; then
  bad "the catalog advertises the bare age image, which does not promise pgvector"
else
  ok "no bare age image in the catalog"
fi

# The PostgreSQL 18 entry is the image this release is meant to run. An AGE bump is
# a deliberate act — existing clusters need a fresh database for it (README,
# "Moving to AGE 1.8.0") — so pin it here rather than letting a revert through.
pg18="$(printf '%s\n' "$rows" | awk '$1 == 18 { print $2 }')"
want18="ghcr.io/konnektr-io/age-pgvector:18-1.8.0-standard-trixie"
if [[ "$pg18" == "$want18" ]]; then
  ok "PostgreSQL 18 runs AGE 1.8.0 ($pg18)"
else
  bad "PostgreSQL 18 entry is '$pg18' (want $want18)"
fi

echo "== documented ways to choose an image"
variant="$(catalog_images --set-json 'cluster.imageCatalog.images=[{"major":18,"image":"ghcr.io/konnektr-io/age-pgvector-postgis:18-1.8.0"}]')"
if [[ "$variant" == "18 ghcr.io/konnektr-io/age-pgvector-postgis:18-1.8.0" ]]; then
  ok "replacing imageCatalog.images switches the variant (postgis renders)"
else
  bad "the documented variant switch did not render: '$variant'"
fi

hatch="$(cluster_spec --set-json 'cluster.imageCatalog.images=[]' \
  --set cluster.cluster.imageName=ghcr.io/konnektr-io/age-pgvector:18-1.8.0-standard-trixie)"
if grep -q '^  imageName: ghcr.io/konnektr-io/age-pgvector:18-1.8.0-standard-trixie$' <<<"$hatch" &&
  ! grep -q 'imageCatalogRef:' <<<"$hatch"; then
  ok "images: [] + imageName pins an image directly (escape hatch)"
else
  bad "the images: [] + imageName escape hatch did not render an imageName-only Cluster"
fi

echo "== bootstrap SQL"
sql="$(cluster_spec | awk '/^      postInitApplicationSQL:/{ inside = 1; next } /^---/{ inside = 0 } inside')"

for statement in \
  'CREATE EXTENSION vector SCHEMA public;' \
  'CREATE EXTENSION age;' \
  'GRANT SELECT ON ag_catalog.ag_graph TO app;' \
  'GRANT USAGE ON SCHEMA ag_catalog TO app;' \
  'ALTER USER app REPLICATION;' \
  'CREATE PUBLICATION age_pub FOR ALL TABLES;' \
  "pg_create_logical_replication_slot('age_slot', 'pgoutput')"
do
  if grep -qF -- "$statement" <<<"$sql"; then
    ok "AGE recipe keeps: $statement"
  else
    bad "AGE recipe lost: $statement"
  fi
done

if ! grep -qF 'postgis' <<<"$sql"; then
  bad "the bootstrap SQL does not create postgis"
elif ! awk '/postgis/ && !/EXCEPTION WHEN OTHERS/ { found = 1 } END { exit !found }' <<<"$sql"; then
  ok "postgis is created defensively (guarded, so it is skipped on images without it)"
else
  bad "an unguarded postgis statement is in the SQL list: that fails the bootstrap of the default age-pgvector image"
fi

echo "== no catalog without a chart-managed cluster"
if helm template "$RELEASE" "$CHART_DIR" --show-only charts/cluster/templates/image-catalog.yaml >/dev/null 2>&1; then
  bad "an ImageCatalog is rendered with cluster.enabled=false"
else
  ok "no ImageCatalog with cluster.enabled=false"
fi

echo "== validation"
expect_render() {
  local desc="$1"
  shift
  if helm template "$RELEASE" "$CHART_DIR" --set cluster.enabled=true "$@" >/dev/null 2>&1; then
    ok "$desc"
  else
    bad "$desc — it was rejected"
  fi
}
expect_reject() {
  local desc="$1"
  shift
  if helm template "$RELEASE" "$CHART_DIR" --set cluster.enabled=true "$@" >/dev/null 2>&1; then
    bad "$desc — it was accepted"
  else
    ok "$desc"
  fi
}

expect_reject "imageName next to a catalog fails (it would be ignored)" \
  --set cluster.cluster.imageName=ghcr.io/konnektr-io/age:18-1.7.0-standard-trixie
expect_reject "cluster.version.major is rejected (nothing reads it)" \
  --set cluster.version.major=17
expect_reject "cluster.version.age is rejected (the AGE release lives in the tags)" \
  --set cluster.version.age=1.7.0
expect_reject "a major with no catalog entry fails" \
  --set-string cluster.version.postgresql=19
expect_reject "imageCatalog.create=false without imageName fails (AGE-less fallback)" \
  --set cluster.imageCatalog.create=false
expect_render "postgresql=17 (an entry exists for it) renders" \
  --set-string cluster.version.postgresql=17

if ((failures > 0)); then
  echo "$failures graph image-catalog check(s) FAILED"
  exit 1
fi
echo "all graph image-catalog checks passed"

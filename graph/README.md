# graph Helm Chart

Deploys the Konnektr Graph API, the events workers and a CloudNativePG
PostgreSQL cluster with **Apache AGE** + **pgvector** — plus PostGIS and/or
TimescaleDB, depending on the image variant you pick.

## Database images

The database images are published by
[`konnektr-io/cnpg-age-containers`](https://github.com/konnektr-io/cnpg-age-containers)
and all bundle AGE on top of a CloudNativePG PostgreSQL image:

| Image variant                     | Extensions                         | Published for (PostgreSQL major) |
| --------------------------------- | ---------------------------------- | -------------------------------- |
| `age-pgvector`                    | AGE, pgvector                      | 16, 17, 18                       |
| `age-pgvector-postgis`            | AGE, pgvector, PostGIS             | 16, 17, 18                       |
| `age-pgvector-timescale`          | AGE, pgvector, TimescaleDB         | 17, 18                           |
| `age-pgvector-postgis-timescale`  | AGE, pgvector, PostGIS, TimescaleDB| 17, 18                           |
| `age`                             | AGE + pgvector, i.e. same content as `age-pgvector` — **not offered** | —                        |

The chart defaults to `age-pgvector` (AGE + pgvector, no PostGIS) on PostgreSQL 18
with **AGE 1.8.0**. The PostgreSQL 16/17 images stay on AGE 1.6.0, the newest AGE
published for those majors. Moving an **existing** cluster onto 1.8.0 is a
backup-and-restore, not a rolling image change — see
[Moving to AGE 1.8.0](#moving-to-age-180).

The bare `age` image is not offered on purpose: it and `age-pgvector` have the
same extension content (pgvector is provided by the CloudNativePG `standard` base
image, which is why no variant installs it per image — see
[cnpg-age-containers#3](https://github.com/konnektr-io/cnpg-age-containers/issues/3)),
and `age` is kept published there only so existing pins keep resolving. Offering
both here would be two names for one image; `age-pgvector*` states the
requirement the Graph has. Verify what an image actually ships with:

```bash
psql -c "SELECT name, default_version FROM pg_available_extensions
          WHERE name IN ('age','vector','postgis','timescaledb') ORDER BY 1;"
```

## Choosing an image variant

The image is chosen once, in `cluster.imageCatalog.images`, and the CNPG `cluster`
subchart turns that list into an `ImageCatalog` and an `imageCatalogRef` with the
major from `cluster.version.postgresql` — the image follows the major instead of a
pinned tag, and `cluster.cluster.imageName` is empty on purpose:

```yaml
cluster:
  enabled: true
  version:
    major: 18
    postgresql: "18"          # the major CloudNativePG resolves from the catalog
  imageCatalog:
    create: true
    images:
      - {major: 16, image: ghcr.io/konnektr-io/age-pgvector:16-1.6.0-standard-trixie}
      - {major: 17, image: ghcr.io/konnektr-io/age-pgvector:17-1.6.0-standard-trixie}
      - {major: 18, image: ghcr.io/konnektr-io/age-pgvector:18-1.8.0-standard-trixie}
```

To run PostGIS, replace that list (the exact block for every variant is in
`values.yaml` next to the setting):

```yaml
cluster:
  imageCatalog:
    images:
      - {major: 18, image: ghcr.io/konnektr-io/age-pgvector-postgis:18-1.7.0}
```

That is the whole change: the bootstrap SQL already creates whatever extensions the
image carries (see below), so nothing else needs overriding. The same applies to
`age-pgvector-timescale` / `age-pgvector-postgis-timescale` (add `timescaledb` to
`shared_preload_libraries` there).

To pin a specific image instead — a digest, or something not in the catalog — empty
the list and use `imageName`:

```yaml
cluster:
  imageCatalog:
    images: []
  cluster:
    imageName: ghcr.io/konnektr-io/age-pgvector@sha256:…
```

The chart fails the render rather than silently picking one when the two are
combined (`imageCatalog.images` wins in the subchart, so a `imageName` next to it
would be ignored), when `version.major` or `version.age` are set (nothing reads
them), when the selected major has no catalog entry, or when the configuration
would fall back to the upstream `<type>` image, which has no AGE at all.

### Moving to AGE 1.8.0

PostgreSQL 18 ships AGE 1.8.0 by default here, which means an existing database on
an older AGE cannot be carried over by swapping the image: AGE ships no upgrade
script, so the extension stays on its old version and then breaks. Measured on the
published images:

| | Result |
|---|---|
| database created by `age-pgvector:18-1.7.0-*`, served by `…:18-1.8.0-*` | `age` stays `1.7.0`; `ALTER EXTENSION age UPDATE` → `ERROR: extension "age" has no update path from version "1.7.0" to version "1.8.0"` |
| reads on that database (`cypher … MATCH … RETURN`) | `ERROR: type with OID 0 does not exist` — every read fails, while `CREATE` still writes, so it breaks quietly |
| a **fresh** database on the same 1.8.0 image | works: `age` 1.8.0, `MATCH` returns rows |

So a **new** cluster is fine and an **existing** one breaks: upgrading a live Graph
across an AGE release is a backup-and-restore onto a fresh cluster (new
`initdb` + data restore, or an export/import of the graph), not an image bump. Plan
it as a migration, and verify the reads afterwards — an AGE mismatch leaves writes
working, so a smoke test that only writes will pass.

## Bootstrap SQL

`cluster.cluster.initdb.postInitApplicationSQL` carries the AGE recipe
(pgvector, AGE, the `ag_catalog` grants, the logical-replication user,
publication and slot). The extensions that only *some* image variants ship
(`postgis`, `postgis_topology`, `fuzzystrmatch`, `postgis_tiger_geocoder`,
`timescaledb`) are created by a single guarded statement: each one is attempted
inside its own exception block, so an extension the image does not provide is
logged and skipped instead of failing the bootstrap. That is why switching
between image variants never requires replacing this list — values lists
replace, they do not merge, so an overridden copy would silently stop receiving
chart fixes.

Notable consequences:

- `vector` and `age` stay unguarded: every supported image ships them, and a
  wrong image should fail loudly.
- The list runs **once**, at `initdb`. Existing clusters keep whatever their
  bootstrap created; changing the list does not touch a running database.
- TimescaleDB needs to be preloaded, so for a `*-timescale*` image also set:

  ```yaml
  cluster:
    cluster:
      postgresql:
        shared_preload_libraries:
          - age
          - timescaledb
  ```

  The extension itself is created by the guarded statement — no SQL override.

### After the image's extensions change

`postInitApplicationSQL` runs **once, at `initdb`**, so it never modifies an
existing database. The library that backs an extension travels with the image, but
the extension's version is fixed when it is created — so when you roll an existing
cluster onto an image that ships a different version, the database keeps the old
one until you reconcile it.

The `age-pgvector*` images shipped pgvector **0.8.6** from an apt package and now
inherit **0.8.7** from the CloudNativePG base image (see
[cnpg-age-containers#3](https://github.com/konnektr-io/cnpg-age-containers/issues/3)),
so after such a roll, run this once against the application database:

```sql
SELECT extversion FROM pg_extension WHERE extname = 'vector';               -- installed
SELECT default_version FROM pg_available_extensions WHERE name = 'vector';  -- shipped by the image
ALTER EXTENSION vector UPDATE;                                              -- no-op when they match
```

```bash
kubectl exec -n <namespace> <cluster>-1 -- \
  psql -U postgres -d app -c 'ALTER EXTENSION vector UPDATE;'
```

Run it as the owner of the extension — the bootstrap superuser (`postgres`, needs
`enableSuperuserAccess: true`, the chart/subchart default), not `app`. It is a
catalog change only: existing ivfflat/HNSW indexes stay valid and there is nothing
to rebuild (verified on a 0.8.6 database served by a 0.8.7 image, index
`indisvalid = 1` before and after), and repeating it is a harmless no-op. New
clusters need nothing. Same procedure for other image changes that bump an
extension the bootstrap SQL created (e.g. a PostGIS rebuild).

## Verifying a change

```bash
helm dependency update graph
helm lint graph --set cluster.enabled=true
./scripts/verify-graph-connection-string.sh
./scripts/verify-graph-image-catalog.sh
```

`scripts/verify-graph-image-catalog.sh` asserts on what the cluster will actually
run: the rendered catalog entries (every entry an `age-pgvector*` image tagged with
its own major, no bare `age`), that the Cluster carries an `imageCatalogRef` and no
`imageName` (so the catalog is the image path, not dead weight), that the documented
variant switch and `images: []` escape hatch render, that the rendered bootstrap SQL
keeps the AGE recipe with PostGIS guarded, and that the contradictory-value cases
above are rejected. Both scripts run in the `test-charts` job of
`Publish Helm Charts`.

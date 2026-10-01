# mega-facecompare-db

| Metadata | |
|---|---|
| Judul | README mega-facecompare-db (compreface-postgres-db) |
| Versi | 2.0.0 |
| Tanggal | 2026-10-01 |
| Owner | Tim Platform / DevOps |
| Status | Review |

| Versi | Tanggal | Penulis | Perubahan |
|---|---|---|---|
| 1.0.0 | 2026-09-29 | Claude Code | Versi awal (di monorepo `services/<service>/README.md`) |
| 2.0.0 | 2026-10-01 | Claude Code | Repo mandiri hasil split monorepo Mega-CompreFace |

**PostgreSQL CompreFace** — image `mega/compreface-postgres-db`. Bagian dari CompreFace (fork Exadel CompreFace 1.2.0, Apache 2.0) yang dipecah
dari monorepo Mega-CompreFace menjadi 6 repo. Integrasi full-stack, monitoring, dokumentasi SDLC (SPEC,
ARCHITECTURE, RUNBOOK, SECURITY, TEST_PLAN) dan versi rilis bersama ada di
[mega-facecompare-deploy](https://scm.bankmegadev.com/cobs/data-management/application/mega-facecompare-deploy).

## Fungsi
Database PostgreSQL 11 untuk admin & api (user, app, collection, subject, embedding, gambar wajah, token OAuth). Skema dibuat/dimigrasi oleh **admin** (Liquibase); image ini hanya menyiapkan ekstensi `uuid-ossp` (`db/initdb.sql`). Menyimpan **data biometrik (UU PDP)**.

Source aplikasi: `db/` (upstream: `initdb.sql`, `Dockerfile` upstream sebagai referensi). **Logika aplikasi upstream tidak diubah** di repo ini; perubahan hanya pada
build, konfigurasi, dan dokumentasi.

## Isi repo
| File | Isi |
|---|---|
| `Dockerfile` | `postgres:11.5` (di-pin digest; major tetap 11 agar kompatibel dengan data live) + `initdb.sql`; `PGDATA=/var/lib/postgresql/data/pgdata` |
| `.dockerignore` | Context: `db/initdb.sql`, `LICENSE`, `NOTICE` |
| `scripts/build.sh` | Build `mega/compreface-postgres-db:<versi>` dari root repo (versi default: file `VERSION`); tulis `build/images.txt` |
| `scripts/push.sh` | Push ke registry (catat digest ke `build/digests.txt`) atau `--save <dir>` → tarball + `SHA256SUMS` untuk transfer air-gapped |
| `k8s/base/` | Manifest service ini saja (Deployment/StatefulSet, Service, ConfigMap, NetworkPolicy) |
| `k8s/overlays/{dev,prod}/` | Overlay per environment untuk service ini |
| `.gitlab-ci.yml` | validate → build → scan (Trivy) → push; registry & kredensial dari variabel CI |
| `.env.example` | Env var service ini (tanpa nilai rahasia) |

## Port & healthcheck
| Port | Healthcheck | Catatan |
|---|---|---|
| 5432 | `pg_isready -U $POSTGRES_USER -d $POSTGRES_DB -h 127.0.0.1` |  |

## Env var
Non-rahasia (ConfigMap `compreface-postgres-db`, default juga di-bake di `Dockerfile`/`.env.example`):

| Variabel | Default | Catatan |
|---|---|---|
| `POSTGRES_DB` | `frs` |  |
| `PGDATA` | `/var/lib/postgresql/data/pgdata` | subdirektori agar aman di PVC |
| `TZ` | `Asia/Jakarta` |  |

Rahasia (Secret Kubernetes — contoh struktur: [k8s/secret.example.yaml](k8s/secret.example.yaml)):

| Variabel | Sumber | Catatan |
|---|---|---|
| `POSTGRES_USER` | Secret `compreface-postgres-credentials` | **wajib** dari Secret / env, tidak pernah di image atau git |
| `POSTGRES_PASSWORD` | Secret `compreface-postgres-credentials` (hanya diterapkan saat inisialisasi volume kosong) | **wajib** dari Secret / env, tidak pernah di image atau git |

Referensi lengkap seluruh service: `docs/CONFIGURATION.md` di repo deploy.

## Build
```bash
scripts/build.sh                       # → mega/compreface-postgres-db:$(cat VERSION)
REGISTRY=registry.example.internal scripts/build.sh && scripts/push.sh
scripts/push.sh --save /media/transfer # air-gapped: docker save + SHA256SUMS → docker load di sisi internal
# manual (build context = root repo, tanpa akses ke repo lain):
docker build -t mega/compreface-postgres-db:1.2.0 .
```
Tag `latest` ditolak. Versi image dinaikkan dengan mengubah `VERSION` + `CHANGELOG.md`; versi yang dirilis
bersama dicatat di `versions.env` repo deploy.

## Run (lokal, tanpa orkestrasi)
```bash
cp .env.example .env    # isi nilai yang ditandai WAJIB
docker run -d --name compreface-postgres-db --env-file .env \
  -v compreface-pgdata:/var/lib/postgresql/data mega/compreface-postgres-db:1.2.0
docker exec compreface-postgres-db pg_isready -d frs -h 127.0.0.1
```
Untuk full-stack (5 service) gunakan `scripts/compose.sh` di repo deploy.

## Kubernetes
```bash
kubectl kustomize k8s/overlays/dev          # render
kubectl apply -k k8s/overlays/dev           # namespace compreface-dev harus sudah ada (dibuat repo deploy)
```
Namespace, NetworkPolicy default-deny + DNS egress, dan Secret dikelola di repo deploy. Repo deploy menyimpan
salinan `k8s/base/` repo ini di `k8s/services/compreface-postgres-db/` — setelah mengubah `k8s/base/`, jalankan
`scripts/sync-manifests.sh` di repo deploy.

## Kontrak ke service lain
Nama Service, port dan nama env var **tidak berubah** dibanding monorepo — perubahannya adalah breaking change
dan harus dikoordinasikan lewat repo deploy.

- **Dipanggil oleh**: `compreface-admin` dan `compreface-api` (`jdbc:postgresql://compreface-postgres-db:5432/frs`). Service headless + ClusterIP bernama `compreface-postgres-db`.
- **Memanggil**: tidak ada.
- Secret `compreface-postgres-credentials` dipakai bersama dengan admin & api.
- Kubernetes: StatefulSet 1 replica + PVC (`volumeClaimTemplates`), `runAsUser/fsGroup 999`, root FS read-only. Overlay prod memakai storage class terenkripsi (`encrypted-block`, sesuaikan). Backup/restore & SQL operasional: repo `mega-facecompare-deploy` (RUNBOOK §5, `scripts/*.sql`).

## Catatan operasional
Major version **tidak boleh** dinaikkan tanpa prosedur migrasi data (pg_upgrade / dump-restore).

## Lisensi
Apache License 2.0 — lihat [LICENSE](LICENSE) dan [NOTICE](NOTICE) (atribusi Exadel, Inc. dipertahankan).

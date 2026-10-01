# Changelog — mega-facecompare-db

Format mengikuti [Keep a Changelog 1.1.0](https://keepachangelog.com/en/1.1.0/); image di-versioning dengan
[SemVer](https://semver.org/) (file `VERSION`). Riwayat sebelum split ada di histori git repo ini
(dibawa dari monorepo dengan `git filter-repo`) dan di `CHANGELOG.md` repo deploy.

## [Unreleased]

## [1.2.0-mega.1] - 2026-10-01

Image: `mega/compreface-postgres-db:1.2.0` (isi aplikasi identik dengan build monorepo Mega-CompreFace `048b77929`).

### Changed
- Repo dipisah dari monorepo Mega-CompreFace (histori path terkait dipertahankan). Build unit
  `services/compreface-postgres-db/` dipindah ke root repo: `Dockerfile`, `.dockerignore`, file pendukung di `docker/`.
- `k8s/base/compreface-postgres-db/` monorepo → `k8s/base/`; overlay `dev`/`prod` khusus service ini (render identik
  dengan objek service ini pada overlay monorepo).

### Added
- `scripts/build.sh` (khusus service ini, versi dari `VERSION`), `scripts/push.sh` (`--save` untuk air-gapped),
  `.gitlab-ci.yml`, `.env.example`, README berisi kontrak antar-service.

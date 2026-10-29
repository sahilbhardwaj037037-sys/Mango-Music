# Mango Music V1 → V2 upgrade and rollback plan

Phase 4A, 29 October 2026 (Asia/Kolkata). **Plan only: no installation, replacement, backup of live data, or real-data migration was performed. Phase 4B has not begun.**

Read-only inspection found `/Applications/Mango Music.app` reporting version 1.0/build 1, identifier `com.localmusic.MangoMusic`, and bundled MangoMusic/mpv/yt-dlp executables byte-identical to the historical Checkpoint 6 staged package. No installed executable was run. The real database header reports schema 2; a header read is not a live WAL-aware database snapshot. Private file hashes of the installed bundle, Application Support directory and preferences were recorded under ignored `.build/phase4a` for before/after comparison. No private library contents are included here.

V2 is staged at `.build/phase4a/output/Mango Music.app`, version 2.0/build 200. The bundle identifier and preference keys remain compatible. Both unsandboxed versions normally use `~/Library/Application Support/MangoMusic/library.sqlite3` and the `com.localmusic.MangoMusic` preferences domain. V2 additionally manages `Downloads` under that Application Support folder. Merely moving an app does not isolate its data. Never launch the staged V2 app directly against the real home during Phase 4A.

## Preparation for a separately authorized Phase 4B

1. Complete the standalone manual checklist in `PHASE4A.md` using its isolated launcher. Resolve any failed checks before installation. Keep the staged artifact and verified signatures available; revalidate immediately before any later copy.
2. Quit installed, Debug and staged Mango Music instances normally. Verify persistence completed, playback stopped and their owned helper PIDs exited. Do not terminate unrelated media processes. No simultaneous V1/V2 access to a library is supported.
3. Create a new private, timestamped backup outside Git. Copy the entire closed `/Applications/Mango Music.app` bundle, preserving resources, permissions and signatures. Record the original bundle version, hashes and signature validation. Preserve this backup unchanged.
4. Back up the **entire closed** `~/Library/Application Support/MangoMusic` directory, including `library.sqlite3`, any `-wal`/`-shm` sidecars, and any Downloads directory. Export the existing `com.localmusic.MangoMusic` preferences domain while closed and retain its original plist if present. Record which paths/domains were absent. Never copy just the main database while an app is running, checkpoint/delete sidecars manually, or put private backups in Git.
5. Verify backup completeness, file counts/hashes, permissions and recoverability before proceeding. Use a duplicate of the backup in a separate test home for an optional actual-library migration rehearsal; keep the original backup immutable. That rehearsal is deferred to a separately authorized phase, since Phase 4A does not copy or migrate real data.
6. Obtain separate Phase 4B authorization for replacement and real-data migration. Recheck destination identity, absence of symlink substitutions, stopped processes, source integrity and backup validity immediately before changing anything. A future replacement must copy a whole bundle using a controlled staged swap, preserve the V1 backup, and never merge bundles. Do not change system security settings or silently use elevated privileges.

## Migration and verification

V2's first successful library open upgrades recognized schema 2 to schema 3 in one transaction. It adds `downloads` and `download_state` without replacing Favorites, History/play counts, Queue identities/order or session metadata. Existing preferences remain under the same keys/domain; new settings use their documented defaults. No audio or download starts automatically after restoration.

Generated fixtures verified schema-v2 migration, independent library/download revisions, transaction rollback, restart recovery and collection preservation. The actual installed library was not opened by V2. A later first launch must compare pre/post migration Favorites, History/counts, Queue identities/order, preferences and stopped-session behavior using the private backup as the baseline. Verify playback, native controls, downloads, restart and quit from the **installed** bundle path; isolated results do not establish installation success. Keep backups until those checks pass.

V2 History retention policies can intentionally remove old entries when selected; changing a policy back cannot recover removed records. Avoid changing retention during migration verification. Preserve the initial backup independently of later V2 backups.

## Rollback

Schema migration is forward-only. The old schema-v2 store was compiled from historical Checkpoint 6 sources and verified to reject the generated v3 database with `newerSchema`. **Restoring only the V1 application is insufficient. Do not edit `PRAGMA user_version` to force a downgrade.**

If rollback is separately authorized, quit all copies and verify owned helpers exited. First preserve the complete failed/current V2 Application Support folder and preferences as a separate private archive, so post-upgrade changes are not destroyed. Restore the whole verified V1 app backup and the **matching pre-upgrade closed Application Support directory and preferences export** as a coherent set. Restore the original absent state for paths/domains that did not exist; do not mix old databases with newer sidecars or leave V2 preference keys in the restored domain. Revalidate signatures, restore private permissions and launch only V1. Verify the backed-up collections/settings and playback before retiring the V2 artifact.

V2-only changes and downloads after the backup will not appear in V1. Retain their separate archive for later recovery with V2; no automatic downgrade, merge or V2-download import into V1 is implemented. Never delete the live library to resolve a schema error.

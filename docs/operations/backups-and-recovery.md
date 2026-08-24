# Backups And Recovery

PostgreSQL WAL archiving and encrypted full/differential backups use
pgBackRest. The repository cipher passphrase and repository credentials are
runtime secrets. The configured example retains seven full and fourteen
differential backup windows; adjust those values to the storage budget before
production.

## Initial setup

1. Create the backup repository with restricted ownership and set
   `BACKUP_REPOSITORY_USER`, `BACKUP_REPOSITORY_PASSWORD`, and
   `BACKUP_ENCRYPTION_KEY` in the private environment file.
2. Start the new stack, create the pgBackRest stanza, and take the first full
   backup:

   ```sh
   docker compose --env-file deploy/.env -f deploy/docker-compose.yml exec backup \
     pgbackrest --stanza=muyu stanza-create
   docker compose --env-file deploy/.env -f deploy/docker-compose.yml exec backup \
     pgbackrest --stanza=muyu check
   docker compose --env-file deploy/.env -f deploy/docker-compose.yml exec backup \
     pgbackrest --stanza=muyu --type=full backup
   ```

3. Schedule full/differential backups using the platform scheduler. Keep WAL
   archiving enabled continuously; a backup is not valid until `check` and a
   restore verification succeed.

## Verification and restore drills

Run the latest-backup verification daily or after backup configuration changes:

```sh
./deploy/scripts/backup-verify.sh
```

The script creates an explicitly named temporary volume/container, restores the
latest backup, runs `pg_isready`, and removes only those temporary resources.
Run a time-targeted drill at least monthly, using a non-production database
name and a checkpoint recorded before the target time:

```sh
TARGET_TIME=2026-08-24T12:00:00Z EXPECTED_CHECKPOINT=123 \
  DRILL_DATABASE=muyu_cloud_restore_drill \
  ./deploy/scripts/restore-drill.sh
```

The drill refuses production database names and fails on cursor/checkpoint
mismatch. Record the restore timestamp, target, observed row counts/cursor,
operator, and backup label in the incident/release log.

## Key and credential loss

If backup credentials are lost, revoke them at the repository provider, issue
new credentials, update the private environment, and run `pgbackrest check` and
a restore verification. If the encryption key is lost, encrypted backups are
unrecoverable; preserve the old key in an approved secret escrow before
rotating. For key rotation, create a new repository/key, take and verify a new
full backup, retain the old repository for its retention window, then revoke
the old key only after a successful drill.

Do not delete the old application's volume during rollback or recovery. The
cloud release is intentionally a separate empty-workspace deployment.

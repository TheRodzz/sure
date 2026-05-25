# PostgreSQL backups with Databasus

Sure’s Docker Compose examples use [Databasus](https://databasus.com/) for PostgreSQL backups instead of a single-purpose local dump container. Databasus provides a web UI to schedule logical backups, keep copies on disk, replicate them to offsite storage, encrypt archives, and notify your team when jobs succeed or fail.

Databasus is a separate open-source project (Apache 2.0). Sure only ships a Compose service definition; backup jobs, storage credentials, and retention are configured in the Databasus dashboard after you start the container.

## What gets backed up

| Data | Covered by Databasus? |
|------|------------------------|
| PostgreSQL (`sure_production` by default) | Yes |
| ActiveStorage uploads (`app-storage` volume) | No - back up separately (see [Application files](#application-files-activestorage) below) |
| Redis | No - usually acceptable to rebuild queues |

## Enable the backup profile

The `databasus` service is behind the `backup` Compose profile so hosts that do not want backups stay unchanged.

```bash
# Standard Sure stack
docker compose --profile backup up -d

# AI compose file
docker compose -f compose.example.ai.yml --profile backup up -d
```

Optional environment variables (in `.env` next to `compose.yml`):

| Variable | Default | Purpose |
|----------|---------|---------|
| `DATABAUS_BIND` | `127.0.0.1:4005` | Host port binding for the UI. Use `0.0.0.0:4005` only behind a firewall or reverse proxy with auth/TLS. |
| `DATABAUS_LOCAL_BACKUP_PATH` | `/opt/sure-data/backups` | Host directory mounted at `/backups` inside the container for **local** backup files |

Create the local backup directory on the host if it does not exist:

```bash
sudo mkdir -p /opt/sure-data/backups
sudo chown "$(id -u)":"$(id -g)" /opt/sure-data/backups
```

## First-time setup

1. Start the stack with the `backup` profile (above).
2. Open the dashboard (default): `http://127.0.0.1:4005`
3. Complete the Databasus admin account setup in the UI.
4. Add your Sure database:
   - **Connection type:** Remote
   - **Host:** `db` (Docker service name on `sure_net`)
   - **Port:** `5432`
   - **Database:** value of `POSTGRES_DB` (default `sure_production`)
   - **User / password:** same as `POSTGRES_USER` / `POSTGRES_PASSWORD` in your `.env`
   - **PostgreSQL version:** 16 (or 16 with pgvector if you use `compose.example.ai.yml`)
5. Configure a **schedule** (for example daily at a low-traffic hour).
6. Add **storage** destinations (see below). Use at least **local** and one **offsite** target for production.
7. Set a **retention** policy (time-based, count-based, or GFS in the UI).
8. Optionally add **notifiers** and **restore verification**.

Databasus validates the connection and runs an initial backup after you save.

### Recommended local + offsite layout

1. **Local storage** - path `/backups` (already mounted from `DATABAUS_LOCAL_BACKUP_PATH`). Fast restores on the same VPS.
2. **Offsite storage** - one or more cloud/object targets (S3, R2, etc.) for disaster recovery if the host is lost.

You can attach multiple destinations to the same backup job so each run writes to local disk and remote storage.

## Supported storage providers

Configure storages in the Databasus UI (**Storages**). Official integrations include:

| Storage | Typical use |
|---------|-------------|
| **Local** | Path `/backups` on the mounted volume |
| **S3** | AWS S3 and S3-compatible APIs (MinIO, Backblaze B2, etc.) |
| **Cloudflare R2** | S3-compatible object storage |
| **Google Drive** | Personal or workspace Drive folders |
| **Azure Blob Storage** | Microsoft Azure |
| **NAS** | Network-attached storage on your LAN |
| **FTP** | Legacy FTP servers |
| **SFTP** | SSH file transfer |
| **rclone** | 70+ additional backends via [rclone](https://rclone.org/) (Wasabi, OneDrive, Google Cloud Storage, Dropbox, etc.) |

For providers without a dedicated tile, use **rclone** and point it at your vendor’s rclone remote name.

Details and credential fields: [Databasus storages documentation](https://databasus.com/storages).

## Supported notification channels

Optional alerts when backups succeed or fail:

| Notifier |
|----------|
| Email |
| Slack |
| Discord |
| Telegram |
| Microsoft Teams |
| Webhook (custom integrations) |

Details: [Databasus notifiers documentation](https://databasus.com/notifiers).

## Security

- **UI exposure:** The example Compose file binds port `4005` to `127.0.0.1` by default. Reach the UI via SSH tunnel, VPN, or a reverse proxy with authentication and TLS-not a public `:4005` on the internet.
- **Database access:** Databasus performs read-only logical backups. Prefer the existing `POSTGRES_USER` only on trusted networks; for stricter setups, create a dedicated PostgreSQL role with `SELECT` on all tables and no write privileges.
- **Encryption:** Backups can be encrypted at rest by Databasus. Export and store the Databasus `secret.key` from `databasus-data` offsite so you can decrypt archives without the UI. See [recover without Databasus](https://databasus.com/how-to-recover-without-databasus).
- **Secrets:** Storage API keys and notifier webhooks are entered in the Databasus UI, not in Sure’s `.env`.

Reset a lost admin password:

```bash
docker compose exec databasus ./main --new-password="YourNewSecurePassword123" --email="admin@example.com"
```

Replace the email with your Databasus admin address.

## Restore a PostgreSQL backup

Use the Databasus UI for one-click restore, or follow Databasus docs to decrypt and restore from S3/local storage without the app.

For a **manual** restore from an old `pg_dump` file left over from the previous `postgres-backup-local` setup:

```bash
docker compose exec -T db psql -U sure_user -d sure_production < /path/to/backup.sql
```

Stop the `web` and `worker` services during destructive restores to avoid concurrent writes.

## Application files (ActiveStorage)

User uploads and other files live in the `app-storage` Docker volume, not in PostgreSQL. Back them up separately, for example:

```bash
docker compose exec -T web tar -czf - /rails/storage > /opt/sure-data/backups/storage_$(date +%Y%m%d).tar.gz
```

Automate with cron on the host. See [Hetzner deployment](hetzner.md) for a combined DB + storage backup pattern.

## Migrating from `postgres-backup-local`

If you previously used the `backup` profile with `prodrigestivill/postgres-backup-local`:

1. Existing files under `/opt/sure-data/backups` (or your custom path) are **not** imported automatically. Keep them until you no longer need them.
2. Replace the old service by pulling the updated `compose.example.yml` and starting `databasus` with `--profile backup`.
3. Configure Databasus as above. New backups will use Databasus naming and encryption settings.
4. Remove duplicate schedules-do not run both the old container and Databasus on the same database.

Upgrading Sure application data, volumes, and user accounts is **unchanged**; enabling Databasus does not migrate or modify the live database.

## Point-in-time recovery (optional)

The Compose examples use **remote** logical backups only (no PostgreSQL configuration changes). For WAL archiving, physical backups, and PITR, Databasus **agent mode** requires extra `postgresql.conf` changes and a host-installed agent. That is outside the default Sure Compose layout; see [Databasus agent installation](https://databasus.com/installation/agent) if you need sub-daily recovery objectives.

## Updating Databasus

Pin the image tag in `compose.yml` for reproducible upgrades, then:

```bash
docker compose pull databasus
docker compose up -d databasus
```

Back up the `databasus-data` volume (or at minimum the encryption `secret.key`) before major upgrades.

## Further reading

- [Databasus documentation](https://databasus.com/)
- [Databasus GitHub](https://github.com/databasus/databasus)
- [Self-hosting Sure with Docker](docker.md)

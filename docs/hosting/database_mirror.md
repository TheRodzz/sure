# Database Mirroring to External PostgreSQL

This guide explains how to set up database mirroring to an external PostgreSQL database (e.g., Supabase) for data durability.

## Overview

Database mirroring replicates all write operations (INSERT, UPDATE, DELETE) from your local Sure database to an external hosted PostgreSQL database. This provides:

- **Data durability**: Your data is backed up in real-time to a cloud provider
- **Non-blocking**: Mirroring runs as background jobs, no performance impact
- **Automatic retries**: Failed operations retry up to 10 times with exponential backoff

## Prerequisites

- A running Sure instance with data you want to mirror
- An external PostgreSQL database (we recommend [Supabase](https://supabase.com))
- `pg_dump` and `pg_restore` tools installed locally

## Setup Guide

### Step 1: Create Your Hosted Database

#### Using Supabase (Recommended)

1. Go to [supabase.com](https://supabase.com) and create a free account
2. Click **New Project** and fill in the details:
   - Name: `sure-mirror` (or your preference)
   - Database Password: Generate a strong password and save it
   - Region: Choose closest to your location
3. Wait for the project to be created (1-2 minutes)
4. Go to **Settings** → **Database** → **Connection string**
5. Copy the **URI** connection string (starts with `postgresql://`)

### Step 2: Initial Data Sync

Before enabling mirroring, you must copy your existing data to the hosted database.

#### Export your local database

```bash
# For Docker Compose setup
docker compose exec db pg_dump -U sure_user -Fc sure_production > backup.dump

# For local PostgreSQL
pg_dump -U postgres -Fc sure_production > backup.dump
```

#### Restore to Supabase

```bash
# Replace with your Supabase connection string
pg_restore -d 'postgresql://postgres:[PASSWORD]@db.[PROJECT].supabase.co:5432/postgres' \
  --clean --if-exists --no-owner --no-privileges backup.dump
```

> [!TIP]
> If you get permission errors, try adding `--no-owner --no-privileges` flags.

### Step 3: Enable Mirroring

Add the `DATABASE_MIRROR_URL` environment variable to your configuration.

#### Docker Compose

Edit your `.env` file:

```bash
DATABASE_MIRROR_URL=postgresql://postgres:[PASSWORD]@db.[PROJECT].supabase.co:5432/postgres
```

Or add directly to `compose.yml`:

```yaml
x-rails-env: &rails_env
  # ... existing vars ...
  DATABASE_MIRROR_URL: postgresql://postgres:[PASSWORD]@db.[PROJECT].supabase.co:5432/postgres
```

#### Direct Installation

Add to your environment:

```bash
export DATABASE_MIRROR_URL=postgresql://postgres:[PASSWORD]@db.[PROJECT].supabase.co:5432/postgres
```

### Step 4: Restart Your Application

```bash
# Docker Compose
docker compose down
docker compose up -d

# Or restart just the services
docker compose restart web worker
```

### Step 5: Verify Mirroring

1. Check the application logs for the mirroring status:
   ```
   [DatabaseMirror] Mirroring enabled to external database
   ```

2. Create a test transaction in Sure

3. Check your Supabase database to verify the record appears:
   - Go to **Table Editor** in Supabase dashboard
   - Look for the new record in the relevant table

4. Check Sidekiq logs for job completion:
   ```
   [DatabaseMirrorJob] Inserted record into entries
   ```

## Troubleshooting

### Connection Errors

**Error**: `[DatabaseMirror] Failed to connect: connection refused`

- Verify your `DATABASE_MIRROR_URL` is correct
- Check if Supabase allows connections from your IP (Settings → Database → Network)
- Ensure the password doesn't contain special characters that need URL encoding

### Schema Mismatch

**Error**: `PG::UndefinedTable` or `PG::UndefinedColumn`

Your hosted database schema is out of sync. Re-run the initial data sync:

```bash
pg_restore -d 'YOUR_CONNECTION_STRING' --clean --if-exists backup.dump
```

### Jobs Failing

Check Sidekiq web UI at `/sidekiq` for failed jobs. Common causes:

- Network timeout: Jobs will retry automatically
- Schema changes: Re-sync the database
- Invalid data: Check logs for specific error messages

## Security Considerations

- Use SSL connections (Supabase enables this by default)
- Restrict database access to your server's IP address
- Use a dedicated database user with minimal privileges if possible
- Keep your `DATABASE_MIRROR_URL` secret - never commit it to version control

## Disabling Mirroring

To disable mirroring, simply remove or unset the `DATABASE_MIRROR_URL` environment variable and restart your application.

```bash
# Remove from .env or compose.yml, then restart
docker compose restart web worker
```

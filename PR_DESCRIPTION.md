# Add Database Mirroring to External PostgreSQL

## Why This Change

**Data durability is critical for self-hosted users.** When running Sure on a local machine or a single VPS, there's no built-in redundancy-if the database is lost, so is all your financial data.

This PR introduces database mirroring, allowing all database writes to be automatically replicated to an external hosted PostgreSQL database (like Supabase). This provides:

- **Disaster recovery** - Quickly restore from the mirror if your local database fails
- **Data backup** - Continuous replication without manual backup scripts
- **Peace of mind** - Know your financial data is safely stored in the cloud

## How It Works

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│  Model Save │ ──▶ │ after_commit│ ──▶ │ Sidekiq Job │ ──▶ │ External DB │
└─────────────┘     └─────────────┘     └─────────────┘     └─────────────┘
```

- Uses ActiveRecord `after_commit` callbacks to enqueue mirror jobs
- Jobs run on **high priority queue** for timely replication
- **Non-blocking** - mirror operations don't slow down your app
- **Retry logic** - exponential backoff (up to 10 attempts) for connection failures
- **Smart schema handling** - only initializes schema if external DB is empty

## Configuration

```bash
DATABASE_MIRROR_ENABLED=true
MIRROR_DB_HOST=db.xxxxx.supabase.co
MIRROR_DB_PORT=5432
MIRROR_DB_NAME=postgres
MIRROR_DB_USER=postgres
MIRROR_DB_PASSWORD=your_password
MIRROR_DB_SSLMODE=require
```

## Changes

### New Files
- `app/models/concerns/mirrorable.rb` - ActiveRecord concern with callbacks
- `app/jobs/database_mirror_job.rb` - Sidekiq job with retry logic
- `app/services/database_mirror_service.rb` - External DB connection & SQL operations
- `config/initializers/database_mirror.rb` - Config validation & schema initialization
- `docs/hosting/database_mirror.md` - User documentation

### Modified Files
- `app/models/application_record.rb` - Include `Mirrorable` concern
- `.env.example` - Document mirror environment variables
- `compose.example.yml` - Add mirror env vars to Docker Compose
- `.devcontainer/docker-compose.yml` - Add `mirror_db` service for local testing

## Testing

Tested successfully with Supabase:
- ✅ Connection established
- ✅ Schema auto-created when database is empty
- ✅ Create/Update/Delete operations mirrored
- ✅ Retry logic handles FK violations from out-of-order jobs
- ✅ Array and JSONB columns properly serialized

## Excluding Models

Models can opt-out of mirroring:

```ruby
class ApiKey < ApplicationRecord
  exclude_from_mirror
end
```

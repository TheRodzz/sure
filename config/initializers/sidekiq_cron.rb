if defined?(Sidekiq::Cron)
  Sidekiq::Cron::Job.create(
    name: "Database Sync",
    cron: ENV.fetch("DB_SYNC_SCHEDULE", "0 * * * *"),
    class: "DatabaseSyncJob"
  )
end

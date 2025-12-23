class DatabaseSyncService
  def sync
    external_db_url = ENV["EXTERNAL_DB_URL"]
    
    if external_db_url.blank?
      Rails.logger.warn("EXTERNAL_DB_URL is not set. Skipping database sync.")
      return
    end

    Rails.logger.info("Starting database sync from external source...")

    # Construct local database URL from environment variables or Rails config
    # We use the Rails configuration to ensure we match what the app is using
    db_config = Rails.configuration.database_configuration[Rails.env]
    
    local_db_url = if ENV["DATABASE_URL"].present?
      ENV["DATABASE_URL"]
    else
      user = db_config["username"] || ENV["POSTGRES_USER"]
      password = db_config["password"] || ENV["POSTGRES_PASSWORD"]
      host = db_config["host"] || ENV["DB_HOST"] || "localhost"
      port = db_config["port"] || ENV["DB_PORT"] || 5432
      database = db_config["database"] || ENV["POSTGRES_DB"]
      
      "postgres://#{user}:#{password}@#{host}:#{port}/#{database}"
    end

    # Use pg_dump to dump the external database and pipe it to psql for the local database
    # -c: Clean (drop) database objects before creating them
    # --no-owner: Do not attempt to restore object ownership (avoid permission issues)
    # --no-acl: Prevent restoration of access privileges (grant/revoke)
    command = "pg_dump \"#{external_db_url}\" --no-owner --no-acl --clean --if-exists --format=plain | psql \"#{local_db_url}\""

    # Execute the command
    # We use system() to execute the command string. 
    # NOTE: Passwords in the URL might be visible in process list if not careful, 
    # but strictly within the container/server context.
    success = system(command)

    if success
      Rails.logger.info("Database sync completed successfully.")
    else
      Rails.logger.error("Database sync failed. Check logs for details.")
      raise "Database sync failed"
    end
  end
end

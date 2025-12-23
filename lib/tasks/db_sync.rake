namespace :db do
  desc "Sync database from EXTERNAL_DB_URL if local database is empty"
  task sync_if_empty: :environment do
    # Check if database schema is loaded/exists by checking if tables exist
    # If no tables (or only ar_internal_metadata/schema_migrations), assume empty
    
    begin
      table_count = ActiveRecord::Base.connection.tables.count
      # Check if we have substantial data, not just migration tracking
      # Usually schema_migrations and ar_internal_metadata are always there if db:prepare ran
      # But if we run this BEFORE db:prepare in entrypoint (or as part of it), behaviour differs.
      # If we run AFTER db:prepare (which runs migrations), table count will include app tables.
      
      # Strategy: Check if specific main tables exist and have data, OR just check if ANY application table exists.
      # Assuming db:prepare runs FIRST (standard Rails entrypoint), the schema will be loaded.
      # So tables will exist but be empty.
      
      # Let's check for 'users' table or similar as a proxy for "application data"
      # Or checking all tables for row count.
      
      has_data = false
      ActiveRecord::Base.connection.tables.each do |table|
        next if ["schema_migrations", "ar_internal_metadata"].include?(table)
        if ActiveRecord::Base.connection.execute("SELECT 1 FROM #{table} LIMIT 1").any?
          has_data = true
          break
        end
      end
      
      if has_data
        puts "Database is not empty. Skipping sync."
      else
        puts "Database is empty. Attempting to sync from external source..."
        if ENV["EXTERNAL_DB_URL"].present?
           DatabaseSyncService.new.sync
        else
           puts "EXTERNAL_DB_URL not set. Skipping."
        end
      end
      
    rescue ActiveRecord::NoDatabaseError
      if ENV["EXTERNAL_DB_URL"].present?
        puts "Database does not exist. Creating and syncing from external source..."
        Rake::Task["db:create"].invoke
        DatabaseSyncService.new.sync
      else
        puts "Database does not exist. Skipping sync check."
      end
    rescue => e
      puts "Error checking database state: #{e.message}"
    end
  end
end

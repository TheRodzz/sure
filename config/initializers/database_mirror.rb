# frozen_string_literal: true

# Database Mirror Configuration
#
# This initializer sets up mirroring of database writes to an external PostgreSQL
# database (e.g., Supabase) for data durability.
#
# Configuration Options:
#   Option 1: Set DATABASE_MIRROR_URL environment variable
#     Example: DATABASE_MIRROR_URL=postgresql://user:password@host:5432/database
#
#   Option 2: Set individual MIRROR_DB_* environment variables:
#     MIRROR_DB_HOST, MIRROR_DB_PORT, MIRROR_DB_USER, MIRROR_DB_PASSWORD,
#     MIRROR_DB_NAME, MIRROR_DB_SSLMODE, MIRROR_DB_PREPARED_STATEMENTS

module DatabaseMirror
  class << self
    def enabled?
      connection_url.present? || mirror_host.present?
    end

    def connection
      return nil unless enabled?

      @connection ||= establish_connection
    end

    def connection_url
      ENV["DATABASE_MIRROR_URL"]
    end

    def reset_connection!
      @connection&.close
      @connection = nil
    end

    private
      def mirror_host
        ENV["MIRROR_DB_HOST"]
      end

      def establish_connection
        if connection_url.present?
          PG.connect(connection_url)
        else
          PG.connect(connection_params)
        end
      rescue PG::Error => e
        Rails.logger.error("[DatabaseMirror] Failed to connect: #{e.message}")
        nil
      end

      def connection_params
        params = {
          host: ENV["MIRROR_DB_HOST"],
          port: ENV.fetch("MIRROR_DB_PORT", 5432),
          user: ENV["MIRROR_DB_USER"],
          password: ENV["MIRROR_DB_PASSWORD"],
          dbname: ENV.fetch("MIRROR_DB_NAME", "postgres")
        }

        # SSL mode
        if ENV["MIRROR_DB_SSLMODE"].present?
          params[:sslmode] = ENV["MIRROR_DB_SSLMODE"]
        end

        # Connection timeout
        if ENV["MIRROR_DB_CONNECT_TIMEOUT"].present?
          params[:connect_timeout] = ENV["MIRROR_DB_CONNECT_TIMEOUT"].to_i
        end

        params
      end
  end
end

# Log mirror status on boot
Rails.application.config.after_initialize do
  if DatabaseMirror.enabled?
    Rails.logger.info("[DatabaseMirror] Mirroring enabled to external database")
  else
    Rails.logger.info("[DatabaseMirror] Mirroring disabled (no mirror database configured)")
  end
end

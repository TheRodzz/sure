# frozen_string_literal: true

# Database Mirror Configuration
#
# This initializer sets up mirroring of database writes to an external PostgreSQL
# database (e.g., Supabase) for data durability.
#
# Configuration:
#   Set DATABASE_MIRROR_URL environment variable to enable mirroring.
#   Example: DATABASE_MIRROR_URL=postgresql://user:password@host:5432/database

module DatabaseMirror
  class << self
    def enabled?
      connection_url.present?
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
      def establish_connection
        PG.connect(connection_url)
      rescue PG::Error => e
        Rails.logger.error("[DatabaseMirror] Failed to connect: #{e.message}")
        nil
      end
  end
end

# Log mirror status on boot
Rails.application.config.after_initialize do
  if DatabaseMirror.enabled?
    Rails.logger.info("[DatabaseMirror] Mirroring enabled to external database")
  else
    Rails.logger.info("[DatabaseMirror] Mirroring disabled (DATABASE_MIRROR_URL not set)")
  end
end

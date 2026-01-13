# frozen_string_literal: true

# DatabaseMirrorJob
#
# Background job that mirrors database write operations to an external
# PostgreSQL database. Uses parameterized queries to prevent SQL injection.

class DatabaseMirrorJob < ApplicationJob
  queue_as :low_priority

  # Retry with exponential backoff for transient failures
  retry_on PG::Error, wait: :polynomially_longer, attempts: 10

  # Discard jobs that can never succeed
  discard_on ActiveJob::DeserializationError

  def perform(model_class_name, record_id, operation, attributes)
    return unless DatabaseMirror.enabled?

    connection = DatabaseMirror.connection
    return unless connection

    table_name = model_class_name.constantize.table_name

    case operation.to_sym
    when :create
      perform_insert(connection, table_name, attributes)
    when :update
      perform_update(connection, table_name, record_id, attributes)
    when :destroy
      perform_delete(connection, table_name, record_id)
    else
      Rails.logger.warn("[DatabaseMirrorJob] Unknown operation: #{operation}")
    end
  rescue PG::Error => e
    Rails.logger.error("[DatabaseMirrorJob] Database error for #{model_class_name}##{record_id}: #{e.message}")
    raise
  rescue StandardError => e
    Rails.logger.error("[DatabaseMirrorJob] Unexpected error for #{model_class_name}##{record_id}: #{e.message}")
    # Don't retry on non-PG errors
  end

  private
    def perform_insert(connection, table_name, attributes)
      return if attributes.empty?

      columns = attributes.keys
      placeholders = columns.each_with_index.map { |_, i| "$#{i + 1}" }
      values = attributes.values

      sql = "INSERT INTO #{quote_identifier(table_name)} (#{columns.map { |c| quote_identifier(c) }.join(', ')}) " \
            "VALUES (#{placeholders.join(', ')}) " \
            "ON CONFLICT (id) DO NOTHING"

      connection.exec_params(sql, values)
      Rails.logger.debug("[DatabaseMirrorJob] Inserted record into #{table_name}")
    end

    def perform_update(connection, table_name, record_id, attributes)
      return if attributes.empty?

      # Remove id from attributes to update
      update_attrs = attributes.except("id")
      return if update_attrs.empty?

      set_clauses = update_attrs.keys.each_with_index.map { |col, i| "#{quote_identifier(col)} = $#{i + 1}" }
      values = update_attrs.values + [ record_id ]

      sql = "UPDATE #{quote_identifier(table_name)} SET #{set_clauses.join(', ')} " \
            "WHERE id = $#{values.length}"

      connection.exec_params(sql, values)
      Rails.logger.debug("[DatabaseMirrorJob] Updated record #{record_id} in #{table_name}")
    end

    def perform_delete(connection, table_name, record_id)
      sql = "DELETE FROM #{quote_identifier(table_name)} WHERE id = $1"
      connection.exec_params(sql, [ record_id ])
      Rails.logger.debug("[DatabaseMirrorJob] Deleted record #{record_id} from #{table_name}")
    end

    # Quote identifier to prevent SQL injection in table/column names
    def quote_identifier(name)
      PG::Connection.quote_ident(name.to_s)
    end
end

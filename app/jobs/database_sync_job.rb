class DatabaseSyncJob < ApplicationJob
  queue_as :default

  def perform
    DatabaseSyncService.new.sync
  end
end

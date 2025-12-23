require 'rails_helper'

RSpec.describe DatabaseSyncService do
  describe '#sync' do
    let(:service) { described_class.new }
    let(:external_db_url) { 'postgres://user:pass@external-host:5432/db' }

    before do
      allow(Rails.logger).to receive(:info)
      allow(Rails.logger).to receive(:error)
      allow(Rails.logger).to receive(:warn)
    end

    context 'when EXTERNAL_DB_URL is set' do
      before do
        allow(ENV).to receive(:[]).with('EXTERNAL_DB_URL').and_return(external_db_url)
        allow(ENV).to receive(:[]).with('DATABASE_URL').and_return(nil)
        allow(ENV).to receive(:[]).with('POSTGRES_USER').and_return('local_user')
        allow(ENV).to receive(:[]).with('POSTGRES_PASSWORD').and_return('local_pass')
        allow(ENV).to receive(:[]).with('DB_HOST').and_return('local_host')
        allow(ENV).to receive(:[]).with('DB_PORT').and_return('5432')
        allow(ENV).to receive(:[]).with('POSTGRES_DB').and_return('local_db')
        
        # Mock Rails config to return some defaults if needed, assuming Standard Rails generic config behavior
        # But verify logic inside service uses Rails.configuration.database_configuration
        allow(Rails.configuration).to receive(:database_configuration).and_return({
          Rails.env => {
            'username' => 'local_user',
            'password' => 'local_pass',
            'host' => 'local_host',
            'port' => 5432,
            'database' => 'local_db'
          }
        })
      end
      
      it 'executes the pg_dump and psql command' do
        expected_command = "pg_dump \"#{external_db_url}\" --no-owner --no-acl --clean --if-exists --format=plain | psql \"postgres://local_user:local_pass@local_host:5432/local_db\""
        
        expect(service).to receive(:system).with(expected_command).and_return(true)
        service.sync
      end

      it 'raises an error if the command fails' do
         allow(service).to receive(:system).and_return(false)
         expect { service.sync }.to raise_error("Database sync failed")
      end
    end

    context 'when EXTERNAL_DB_URL is missing' do
      before do
        allow(ENV).to receive(:[]).with('EXTERNAL_DB_URL').and_return(nil)
      end

      it 'logs a warning and does not execute system command' do
        expect(Rails.logger).to receive(:warn).with(/EXTERNAL_DB_URL is not set/)
        expect(service).not_to receive(:system)
        service.sync
      end
    end
  end
end

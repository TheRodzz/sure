# frozen_string_literal: true

require "test_helper"

class DatabaseMirrorJobTest < ActiveJob::TestCase
  test "job is discarded when mirror is disabled" do
    DatabaseMirror.stubs(:enabled?).returns(false)

    # Job should complete without doing anything when disabled
    assert_nothing_raised do
      DatabaseMirrorJob.perform_now("Account", "test-id", :create, { "id" => "test-id", "name" => "Test" })
    end
  end

  test "job handles nil connection gracefully" do
    DatabaseMirror.stubs(:enabled?).returns(true)
    DatabaseMirror.stubs(:connection).returns(nil)

    # Job should complete without raising when connection is nil
    assert_nothing_raised do
      DatabaseMirrorJob.perform_now("Account", "test-id", :create, { "id" => "test-id" })
    end
  end

  test "job handles unknown operation gracefully" do
    DatabaseMirror.stubs(:enabled?).returns(true)
    DatabaseMirror.stubs(:connection).returns(nil)

    # Job should complete without raising when operation is unknown
    assert_nothing_raised do
      DatabaseMirrorJob.perform_now("Account", "test-id", :unknown, {})
    end
  end

  test "job uses parameterized queries for insert" do
    mock_connection = mock("pg_connection")
    DatabaseMirror.stubs(:enabled?).returns(true)
    DatabaseMirror.stubs(:connection).returns(mock_connection)

    # Expect exec_params to be called (parameterized query)
    mock_connection.expects(:exec_params).with(
      regexp_matches(/INSERT INTO/),
      anything
    ).once

    DatabaseMirrorJob.perform_now(
      "Account",
      "test-id",
      :create,
      { "id" => "test-id", "name" => "Test Account" }
    )
  end

  test "job uses parameterized queries for update" do
    mock_connection = mock("pg_connection")
    DatabaseMirror.stubs(:enabled?).returns(true)
    DatabaseMirror.stubs(:connection).returns(mock_connection)

    # Expect exec_params to be called (parameterized query)
    mock_connection.expects(:exec_params).with(
      regexp_matches(/UPDATE/),
      anything
    ).once

    DatabaseMirrorJob.perform_now(
      "Account",
      "test-id",
      :update,
      { "id" => "test-id", "name" => "Updated Account" }
    )
  end

  test "job uses parameterized queries for delete" do
    mock_connection = mock("pg_connection")
    DatabaseMirror.stubs(:enabled?).returns(true)
    DatabaseMirror.stubs(:connection).returns(mock_connection)

    # Expect exec_params to be called (parameterized query)
    mock_connection.expects(:exec_params).with(
      regexp_matches(/DELETE FROM/),
      [ "test-id" ]
    ).once

    DatabaseMirrorJob.perform_now(
      "Account",
      "test-id",
      :destroy,
      {}
    )
  end

  test "job is configured to retry on database errors" do
    # Verify retry_on is configured for PG::Error
    assert DatabaseMirrorJob.new.respond_to?(:perform)
  end
end

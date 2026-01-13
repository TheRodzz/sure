# frozen_string_literal: true

require "test_helper"

class MirrorableTest < ActiveJob::TestCase
  test "mirrors create when enabled" do
    DatabaseMirror.stubs(:enabled?).returns(true)

    assert_enqueued_with(job: DatabaseMirrorJob) do
      Category.create!(
        name: "Test Category #{SecureRandom.hex(4)}",
        family: families(:dylan_family)
      )
    end
  end

  test "does not mirror create when disabled" do
    DatabaseMirror.stubs(:enabled?).returns(false)

    assert_no_enqueued_jobs(only: DatabaseMirrorJob) do
      Category.create!(
        name: "Test Category 2 #{SecureRandom.hex(4)}",
        family: families(:dylan_family)
      )
    end
  end

  test "mirrors update when enabled" do
    DatabaseMirror.stubs(:enabled?).returns(true)
    category = categories(:food_and_drink)

    assert_enqueued_with(job: DatabaseMirrorJob) do
      category.update!(name: "Updated Food #{SecureRandom.hex(4)}")
    end
  end

  test "mirrors destroy when enabled" do
    # Create a category to destroy with mirroring disabled
    DatabaseMirror.stubs(:enabled?).returns(false)
    category = Category.create!(
      name: "To Delete #{SecureRandom.hex(4)}",
      family: families(:dylan_family)
    )

    # Enable mirroring and destroy
    DatabaseMirror.stubs(:enabled?).returns(true)

    assert_enqueued_with(job: DatabaseMirrorJob) do
      category.destroy!
    end
  end

  test "serializes hash values to json" do
    record = Category.new(name: "Test", family: families(:dylan_family))
    attrs = record.send(:mirrorable_attributes)

    # Check that attributes are returned
    assert attrs.key?("name")
    assert_equal "Test", attrs["name"]
  end
end

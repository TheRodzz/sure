# frozen_string_literal: true

# Mirrorable Concern
#
# Automatically mirrors database write operations (create, update, destroy)
# to an external PostgreSQL database via background jobs.
#
# Usage:
#   Include in ApplicationRecord to enable for all models, or include
#   in specific models as needed.

module Mirrorable
  extend ActiveSupport::Concern

  included do
    after_create_commit :mirror_create, if: -> { DatabaseMirror.enabled? }
    after_update_commit :mirror_update, if: -> { DatabaseMirror.enabled? }
    after_destroy_commit :mirror_destroy, if: -> { DatabaseMirror.enabled? }
  end

  private
    def mirror_create
      DatabaseMirrorJob.perform_later(
        self.class.name,
        id,
        :create,
        mirrorable_attributes
      )
    end

    def mirror_update
      DatabaseMirrorJob.perform_later(
        self.class.name,
        id,
        :update,
        mirrorable_attributes
      )
    end

    def mirror_destroy
      DatabaseMirrorJob.perform_later(
        self.class.name,
        id,
        :destroy,
        {}
      )
    end

    def mirrorable_attributes
      attributes.transform_values do |value|
        serialize_for_mirror(value)
      end
    end

    def serialize_for_mirror(value)
      case value
      when Array
        value.to_json
      when Hash
        value.to_json
      when Time, DateTime
        value.iso8601
      when Date
        value.to_s
      when BigDecimal
        value.to_s("F")
      else
        value
      end
    end
end

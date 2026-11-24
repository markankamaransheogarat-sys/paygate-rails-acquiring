# frozen_string_literal: true

class WebhookDelivery < ApplicationRecord
  STATUSES = %w[pending processing delivered dead].freeze

  belongs_to :payment
  belongs_to :merchant

  validates :event_type, :target_url, :signature, :status, presence: true
  validates :status, inclusion: { in: STATUSES }
end

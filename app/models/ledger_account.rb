# frozen_string_literal: true

class LedgerAccount < ApplicationRecord
  TYPES = %w[psp_clearing available reserve fee_revenue refund_liability chargeback_loss].freeze

  belongs_to :merchant, optional: true

  validates :currency, :account_type, presence: true
  validates :account_type, inclusion: { in: TYPES }
end

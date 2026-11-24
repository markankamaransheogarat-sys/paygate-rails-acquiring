# frozen_string_literal: true

class LedgerEntry < ApplicationRecord
  KINDS = %w[capture_gross merchant_fee rolling_reserve refund chargeback_debit].freeze

  belongs_to :payment
  belongs_to :debit_account, class_name: "LedgerAccount"
  belongs_to :credit_account, class_name: "LedgerAccount"

  validates :amount_minor, numericality: { greater_than: 0 }
  validates :currency, :entry_kind, :idempotency_key, presence: true
  validates :entry_kind, inclusion: { in: KINDS }
end

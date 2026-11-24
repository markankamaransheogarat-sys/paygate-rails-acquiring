# frozen_string_literal: true

class Payment < ApplicationRecord
  STATUSES = %w[pending processing captured partially_refunded refunded failed chargeback].freeze
  METHODS = %w[card sbp p2p upi ewallet].freeze
  CURRENCIES = %w[RUB KZT UZS INR THB USD USDT].freeze

  belongs_to :merchant
  belongs_to :psp_provider, optional: true
  has_many :ledger_entries, dependent: :restrict_with_exception
  has_many :webhook_deliveries, dependent: :restrict_with_exception

  validates :idempotency_key, :external_order_id, :currency, :payment_method, :region, :status, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :payment_method, inclusion: { in: METHODS }
  validates :currency, inclusion: { in: CURRENCIES }
  validates :amount_minor, numericality: { greater_than: 0 }

  def refundable_amount_minor
    amount_minor - refunded_amount_minor
  end

  def terminal_state?
    %w[refunded failed chargeback].include?(status)
  end
end

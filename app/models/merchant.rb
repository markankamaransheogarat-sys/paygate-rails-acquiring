# frozen_string_literal: true

class Merchant < ApplicationRecord
  has_many :payments, dependent: :restrict_with_exception
  has_many :ledger_accounts, dependent: :restrict_with_exception
  has_many :webhook_deliveries, dependent: :restrict_with_exception

  scope :active, -> { where(active: true) }

  validates :code, :name, :api_key, :api_secret, presence: true
  validates :code, :api_key, uniqueness: true
  validates :fee_bps, :rolling_reserve_bps, numericality: { in: 0..5000 }
end

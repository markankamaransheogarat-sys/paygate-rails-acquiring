# frozen_string_literal: true

class PspProvider < ApplicationRecord
  REGIONS = %w[CIS ASIA GLOBAL].freeze

  has_many :payments, dependent: :restrict_with_exception

  scope :active, -> { where(active: true) }

  validates :code, :name, :region, :webhook_secret, presence: true
  validates :code, uniqueness: true
  validates :region, inclusion: { in: REGIONS }
  validates :priority, :cost_bps, numericality: { greater_than_or_equal_to: 0 }
end

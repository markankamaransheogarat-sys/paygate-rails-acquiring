# frozen_string_literal: true

module Contracts
  module Payments
    class CreateContract < ApplicationContract
      params do
        required(:idempotency_key).filled(:string, min_size?: 8, max_size?: 128)
        required(:external_order_id).filled(:string, min_size?: 1, max_size?: 128)
        required(:amount_minor).filled(:integer, gt?: 0)
        required(:currency).filled(:string, included_in?: Payment::CURRENCIES)
        required(:payment_method).filled(:string, included_in?: Payment::METHODS)
        required(:region).filled(:string, included_in?: PspProvider::REGIONS)
        optional(:customer_payload).hash do
          optional(:customer_id).filled(:string)
          optional(:ip).filled(:string)
          optional(:country).filled(:string, size?: 2)
          optional(:card_bin).filled(:string, size?: 6..8)
        end
      end

      rule(:currency, :region) do
        if values[:region] == "CIS" && !%w[RUB KZT UZS USD USDT].include?(values[:currency])
          key(:currency).failure("is not supported for CIS acquiring")
        elsif values[:region] == "ASIA" && !%w[INR THB USD USDT].include?(values[:currency])
          key(:currency).failure("is not supported for ASIA acquiring")
        end
      end
    end
  end
end

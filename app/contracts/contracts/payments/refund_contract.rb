# frozen_string_literal: true

module Contracts
  module Payments
    class RefundContract < ApplicationContract
      params do
        required(:payment_id).filled(:string)
        required(:amount_minor).filled(:integer, gt?: 0)
        required(:idempotency_key).filled(:string, min_size?: 6, max_size?: 128)
        optional(:reason).filled(:string, max_size?: 255)
      end
    end
  end
end

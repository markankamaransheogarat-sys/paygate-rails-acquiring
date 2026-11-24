# frozen_string_literal: true

module Contracts
  module Webhooks
    class PspCallbackContract < ApplicationContract
      ALLOWED_EVENTS = %w[captured failed chargeback].freeze

      params do
        required(:psp_transaction_id).filled(:string)
        required(:payment_id).filled(:string)
        required(:event).filled(:string, included_in?: ALLOWED_EVENTS)
        optional(:failure_code).maybe(:string)
        optional(:failure_reason).maybe(:string)
      end
    end
  end
end

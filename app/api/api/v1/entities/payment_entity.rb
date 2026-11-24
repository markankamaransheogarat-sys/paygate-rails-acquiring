# frozen_string_literal: true

module Api
  module V1
    module Entities
      class PaymentEntity < Grape::Entity
        expose :id
        expose :external_order_id
        expose :psp_transaction_id
        expose :status
        expose :amount_minor
        expose :refunded_amount_minor
        expose :currency
        expose :payment_method
        expose :region
        expose :cascade_attempts
        expose :cascade_trace
        expose :failure_code
        expose :failure_reason
        expose :captured_at
        expose :created_at
        expose :psp_code do |payment|
          payment.psp_provider&.code
        end
      end
    end
  end
end

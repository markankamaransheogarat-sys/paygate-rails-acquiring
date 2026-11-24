# frozen_string_literal: true

module Api
  module V1
    class PaymentsApi < Grape::API
      helpers Api::V1::Helpers::AuthHelper

      before { authenticate_merchant! }

      resource :payments do
        desc "Create a payment with automatic multi-PSP cascade routing"
        post do
          payload = params.to_h.symbolize_keys
          payload[:idempotency_key] ||= headers["X-Idempotency-Key"] || headers["x-idempotency-key"]

          result = ::Payments::Create.new.call(merchant: current_merchant, params: payload)

          if result.success?
            data = result.value!
            status(data[:idempotent_replay] ? 200 : 201)
            {
              idempotent_replay: data[:idempotent_replay],
              payment: Api::V1::Entities::PaymentEntity.represent(data[:payment])
            }
          else
            code, details = result.failure
            http_status = code == :validation_error ? 422 : 503
            error!({ error: code, details: details }, http_status)
          end
        end

        desc "Fetch payment status and cascade trace"
        get ":id" do
          payment = current_merchant.payments.includes(:psp_provider).find_by(id: params[:id])
          error!({ error: "not_found", message: "Payment not found" }, 404) unless payment

          { payment: Api::V1::Entities::PaymentEntity.represent(payment) }
        end

        desc "Issue full or partial refund"
        post ":id/refunds" do
          payload = params.to_h.symbolize_keys.merge(payment_id: params[:id])
          payload[:idempotency_key] ||= headers["X-Idempotency-Key"] || headers["x-idempotency-key"]

          result = ::Payments::IssueRefund.new.call(merchant: current_merchant, params: payload)

          if result.success?
            data = result.value!
            status(data[:idempotent_replay] ? 200 : 201)
            {
              idempotent_replay: data[:idempotent_replay],
              payment: Api::V1::Entities::PaymentEntity.represent(data[:payment])
            }
          else
            code, details = result.failure
            http_status = case code
            when :payment_not_found then 404
            when :validation_error, :invalid_state, :amount_exceeds_refundable, :insufficient_funds then 422
            else 400
            end
            error!({ error: code, details: details }, http_status)
          end
        end
      end
    end
  end
end

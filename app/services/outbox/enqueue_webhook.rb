# frozen_string_literal: true

module Outbox
  class EnqueueWebhook
    def self.call(payment:, merchant:, event_type:)
      return if merchant.webhook_url.blank?

      payload = {
        event: event_type,
        payment_id: payment.id,
        external_order_id: payment.external_order_id,
        status: payment.status,
        amount_minor: payment.amount_minor,
        refunded_amount_minor: payment.refunded_amount_minor,
        currency: payment.currency,
        psp_code: payment.psp_provider&.code,
        occurred_at: Time.current.iso8601
      }

      signature = Security::HmacSigner.sign(secret: merchant.api_secret, payload: payload)

      WebhookDelivery.create!(
        payment: payment,
        merchant: merchant,
        event_type: event_type,
        target_url: merchant.webhook_url,
        payload: payload,
        signature: signature,
        status: "pending",
        next_attempt_at: Time.current
      )
    end
  end
end

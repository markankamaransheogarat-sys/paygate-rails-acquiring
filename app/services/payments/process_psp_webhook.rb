# frozen_string_literal: true

module Payments
  class ProcessPspWebhook
    include Dry::Monads[:result, :do]

    UPDATE_HEALTH_SQL = <<~SQL.squish
      UPDATE psp_providers
      SET health_score = LEAST(100.0, GREATEST(0.0, health_score + :delta)),
          updated_at = NOW()
      WHERE id = :id
    SQL

    def initialize(
      contract: Contracts::Webhooks::PspCallbackContract.new,
      ledger: Ledger::PostEntry.new,
      notifier: Telegram::BotService.new
    )
      @contract = contract
      @ledger = ledger
      @notifier = notifier
    end

    def call(provider_code:, raw_body:, signature:, params:)
      psp = PspProvider.find_by(code: provider_code)
      return Failure([ :psp_not_found, "Unknown PSP #{provider_code}" ]) unless psp

      unless Security::HmacSigner.valid?(secret: psp.webhook_secret, payload: raw_body, signature: signature)
        return Failure([ :invalid_signature, "PSP HMAC signature mismatch" ])
      end

      validated = yield validate(params)
      apply_transition(psp: psp, payload: validated)
    end

    private

    def validate(params)
      res = @contract.call(params)
      res.success? ? Success(res.to_h) : Failure([ :validation_error, res.errors.to_h ])
    end

    def apply_transition(psp:, payload:)
      payment = Payment.find_by(id: payload[:payment_id])
      return Failure([ :payment_not_found, "Payment #{payload[:payment_id]} not found" ]) unless payment

      event = payload[:event]

      ActiveRecord::Base.transaction do
        payment.lock!

        if payment.status == event
          return Success(payment: payment, idempotent_replay: true)
        end

        case event
        when "captured"
          return Failure([ :invalid_transition, "Cannot capture from #{payment.status}" ]) unless %w[pending processing].include?(payment.status)

          payment.update!(
            psp_provider: psp,
            psp_transaction_id: payload[:psp_transaction_id],
            status: "captured",
            captured_at: Time.current
          )
          @ledger.record_capture_settlement!(payment: payment, merchant: payment.merchant)
          Outbox::EnqueueWebhook.call(payment: payment, merchant: payment.merchant, event_type: "payment.captured")
          adjust_psp_health(psp.id, +0.5)
        when "failed"
          return Failure([ :invalid_transition, "Cannot fail from #{payment.status}" ]) unless %w[pending processing].include?(payment.status)

          payment.update!(
            psp_provider: psp,
            psp_transaction_id: payload[:psp_transaction_id],
            status: "failed",
            failure_code: payload[:failure_code] || "psp_callback_failed",
            failure_reason: payload[:failure_reason]
          )
          Outbox::EnqueueWebhook.call(payment: payment, merchant: payment.merchant, event_type: "payment.failed")
          adjust_psp_health(psp.id, -2.5)
        when "chargeback"
          return Failure([ :invalid_transition, "Cannot chargeback from #{payment.status}" ]) unless %w[captured partially_refunded].include?(payment.status)

          available = Ledger::PostEntry.ensure_account!(merchant_id: payment.merchant_id, currency: payment.currency, account_type: "available")
          cb_loss = Ledger::PostEntry.ensure_account!(merchant_id: nil, currency: payment.currency, account_type: "chargeback_loss")
          debit_amount = payment.refundable_amount_minor

          if debit_amount.positive?
            @ledger.call(
              payment: payment,
              debit_account: available,
              credit_account: cb_loss,
              amount_minor: debit_amount,
              entry_kind: "chargeback_debit",
              idempotency_key: "chargeback:#{payment.id}"
            )
          end

          payment.update!(status: "chargeback", failure_code: payload[:failure_code] || "chargeback")
          Outbox::EnqueueWebhook.call(payment: payment, merchant: payment.merchant, event_type: "payment.chargeback")
          adjust_psp_health(psp.id, -5.0)
          @notifier.notify("<b>CHARGEBACK ALERT</b>\nMerchant: <code>#{payment.merchant.code}</code>\nPayment: <code>#{payment.id}</code>\nAmount: #{debit_amount} #{payment.currency}")
        end
      end

      Success(payment: payment.reload, idempotent_replay: false)
    end

    def adjust_psp_health(psp_id, delta)
      sql = ActiveRecord::Base.sanitize_sql_array([ UPDATE_HEALTH_SQL, { id: psp_id, delta: delta } ])
      ActiveRecord::Base.connection.exec_update(sql)
    end
  end
end

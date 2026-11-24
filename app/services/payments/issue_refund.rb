# frozen_string_literal: true

module Payments
  class IssueRefund
    include Dry::Monads[:result, :do]

    def initialize(
      contract: Contracts::Payments::RefundContract.new,
      ledger: Ledger::PostEntry.new
    )
      @contract = contract
      @ledger = ledger
    end

    def call(merchant:, params:)
      validated = yield validate(params)
      payment = Payment.find_by(id: validated[:payment_id], merchant_id: merchant.id)
      return Failure([ :payment_not_found, "Payment not found" ]) unless payment

      amount_minor = validated[:amount_minor]
      entry_key = "refund:#{payment.id}:#{validated[:idempotency_key]}"

      if LedgerEntry.exists?(idempotency_key: entry_key)
        return Success(payment: payment, idempotent_replay: true)
      end

      ActiveRecord::Base.transaction do
        payment.lock!

        unless %w[captured partially_refunded].include?(payment.status)
          return Failure([ :invalid_state, "Payment status '#{payment.status}' is not refundable" ])
        end

        if amount_minor > payment.refundable_amount_minor
          return Failure([ :amount_exceeds_refundable, "Max refundable is #{payment.refundable_amount_minor}" ])
        end

        available = Ledger::PostEntry.ensure_account!(merchant_id: merchant.id, currency: payment.currency, account_type: "available")
        refund_liability = Ledger::PostEntry.ensure_account!(merchant_id: nil, currency: payment.currency, account_type: "refund_liability")

        ledger_result = @ledger.call(
          payment: payment,
          debit_account: available,
          credit_account: refund_liability,
          amount_minor: amount_minor,
          entry_kind: "refund",
          idempotency_key: entry_key,
          enforce_non_negative_debit: true,
          metadata: { reason: validated[:reason] }.compact
        )

        return ledger_result if ledger_result.failure?

        new_refunded = payment.refunded_amount_minor + amount_minor
        new_status = new_refunded == payment.amount_minor ? "refunded" : "partially_refunded"
        payment.update!(refunded_amount_minor: new_refunded, status: new_status)

        Outbox::EnqueueWebhook.call(payment: payment, merchant: merchant, event_type: "payment.refunded")
      end

      Success(payment: payment.reload, idempotent_replay: false)
    end

    private

    def validate(params)
      res = @contract.call(params)
      res.success? ? Success(res.to_h) : Failure([ :validation_error, res.errors.to_h ])
    end
  end
end

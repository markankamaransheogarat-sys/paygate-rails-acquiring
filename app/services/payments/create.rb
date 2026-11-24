# frozen_string_literal: true

module Payments
  class Create
    include Dry::Monads[:result, :do]

    def initialize(
      contract: Contracts::Payments::CreateContract.new,
      gateway: Psp::HttpGateway.new,
      ledger: Ledger::PostEntry.new,
      notifier: Telegram::BotService.new
    )
      @contract = contract
      @gateway = gateway
      @ledger = ledger
      @notifier = notifier
    end

    def call(merchant:, params:)
      validated = yield validate(params)

      existing = Payment.find_by(merchant_id: merchant.id, idempotency_key: validated[:idempotency_key])
      return Success(payment: existing, idempotent_replay: true) if existing

      psps = yield select_cascade(merchant: merchant, params: validated)
      payment = create_initial_payment(merchant: merchant, params: validated)
      execute_cascade(payment: payment, merchant: merchant, psps: psps)
    rescue ActiveRecord::RecordNotUnique
      replay = Payment.find_by!(merchant_id: merchant.id, idempotency_key: params[:idempotency_key].to_s)
      Success(payment: replay, idempotent_replay: true)
    end

    private

    def validate(params)
      res = @contract.call(params)
      res.success? ? Success(res.to_h) : Failure([ :validation_error, res.errors.to_h ])
    end

    def select_cascade(merchant:, params:)
      rules = merchant.custom_routing_rules || {}
      psps = Queries::Routing::EligiblePspsQuery.call(
        region: params[:region],
        currency: params[:currency],
        amount_minor: params[:amount_minor],
        preferred_code: rules["preferred_psp"],
        excluded_codes: rules["excluded_psps"] || []
      )

      psps.any? ? Success(psps) : Failure([ :no_eligible_psp, "No active PSP for #{params[:region]}/#{params[:currency]}" ])
    end

    def create_initial_payment(merchant:, params:)
      Payment.create!(
        merchant: merchant,
        idempotency_key: params[:idempotency_key],
        external_order_id: params[:external_order_id],
        amount_minor: params[:amount_minor],
        currency: params[:currency],
        payment_method: params[:payment_method],
        region: params[:region],
        status: "processing",
        customer_payload: params[:customer_payload] || {}
      )
    end

    def execute_cascade(payment:, merchant:, psps:)
      trace = []
      attempts = 0

      psps.each do |psp|
        attempts += 1
        result = @gateway.charge(psp: psp, payment: payment)

        if result.success?
          data = result.value!
          trace << { psp: psp["code"], attempt: attempts, outcome: data[:status], at: Time.current.iso8601 }
          finalize_success!(payment: payment, merchant: merchant, psp_id: psp["id"], data: data, attempts: attempts, trace: trace)
          return Success(payment: payment.reload, idempotent_replay: false)
        end

        code, reason, retryable = result.failure
        trace << { psp: psp["code"], attempt: attempts, outcome: "failed", code: code, reason: reason, retryable: retryable, at: Time.current.iso8601 }
        break unless retryable
      end

      last = trace.last || {}
      finalize_failure!(payment: payment, merchant: merchant, attempts: attempts, trace: trace, code: last[:code], reason: last[:reason])
      Success(payment: payment.reload, idempotent_replay: false)
    end

    def finalize_success!(payment:, merchant:, psp_id:, data:, attempts:, trace:)
      ActiveRecord::Base.transaction do
        payment.update!(
          psp_provider_id: psp_id,
          psp_transaction_id: data[:psp_transaction_id],
          status: data[:status],
          cascade_attempts: attempts,
          cascade_trace: trace,
          captured_at: (data[:status] == "captured" ? Time.current : nil)
        )

        if data[:status] == "captured"
          @ledger.record_capture_settlement!(payment: payment, merchant: merchant)
          Outbox::EnqueueWebhook.call(payment: payment, merchant: merchant, event_type: "payment.captured")
        end
      end
    end

    def finalize_failure!(payment:, merchant:, attempts:, trace:, code:, reason:)
      ActiveRecord::Base.transaction do
        payment.update!(
          status: "failed",
          cascade_attempts: attempts,
          cascade_trace: trace,
          failure_code: code || "cascade_exhausted",
          failure_reason: reason || "All PSPs in cascade declined"
        )

        Outbox::EnqueueWebhook.call(payment: payment, merchant: merchant, event_type: "payment.failed")
      end

      @notifier.notify("<b>Payment cascade failed</b>\nOrder: <code>#{payment.external_order_id}</code>\nAttempts: #{attempts}\nCode: <code>#{payment.failure_code}</code>")
    end
  end
end

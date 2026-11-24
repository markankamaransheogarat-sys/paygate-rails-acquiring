# frozen_string_literal: true

module Psp
  class HttpGateway
    include Dry::Monads[:result]

    DEFAULT_TIMEOUT_SECONDS = 5

    def initialize(base_url: ENV.fetch("PSP_GATEWAY_BASE_URL", "https://psp-sandbox.internal"))
      @base_url = base_url
    end

    def charge(psp:, payment:)
      conn = Faraday.new(url: @base_url) do |f|
        f.options.timeout = DEFAULT_TIMEOUT_SECONDS
        f.options.open_timeout = 2
        f.request :json
        f.response :json
      end

      response = conn.post("/v1/providers/#{psp.fetch('code')}/charges") do |req|
        req.headers["X-Idempotency-Key"] = payment.id
        req.headers["X-PSP-Signature"] = Security::HmacSigner.sign(
          secret: psp.fetch("webhook_secret"),
          payload: charge_body(payment)
        )
        req.body = charge_body(payment)
      end

      parse_response(response)
    rescue Faraday::TimeoutError, Faraday::ConnectionFailed => e
      Failure([ :psp_network_error, e.message, true ])
    end

    private

    def charge_body(payment)
      {
        payment_id: payment.id,
        external_order_id: payment.external_order_id,
        amount_minor: payment.amount_minor,
        currency: payment.currency,
        payment_method: payment.payment_method,
        region: payment.region,
        customer: payment.customer_payload
      }
    end

    def parse_response(response)
      body = response.body.is_a?(Hash) ? response.body : {}

      if response.success? && %w[captured processing].include?(body["status"])
        Success(
          status: body["status"],
          psp_transaction_id: body.fetch("transaction_id"),
          raw: body
        )
      elsif response.status >= 500 || response.status == 429 || body["retryable"] == true
        Failure([ body["code"] || "psp_unavailable", body["message"] || "HTTP #{response.status}", true ])
      else
        Failure([ body["code"] || "psp_declined", body["message"] || "Declined (HTTP #{response.status})", false ])
      end
    end
  end
end

# frozen_string_literal: true

module Outbox
  class DispatchWebhooks
    MAX_ATTEMPTS = 5

    def initialize(notifier: Telegram::BotService.new)
      @notifier = notifier
    end

    def call(batch_size: 25)
      rows = Queries::Outbox::ClaimDueWebhooksQuery.call(limit: batch_size)
      results = { delivered: 0, retried: 0, dead: 0 }

      rows.each do |row|
        outcome = deliver_row(row)
        results[outcome] += 1
      end

      results
    end

    private

    def deliver_row(row)
      payload = row["payload"].is_a?(String) ? JSON.parse(row["payload"]) : row["payload"]
      conn = Faraday.new do |f|
        f.options.timeout = 4
        f.options.open_timeout = 2
        f.request :json
      end

      resp = conn.post(row["target_url"]) do |req|
        req.headers["Content-Type"] = "application/json"
        req.headers["X-Paygate-Event"] = row["event_type"]
        req.headers["X-Paygate-Signature"] = row["signature"]
        req.body = payload
      end

      if resp.success?
        WebhookDelivery.where(id: row["id"]).update_all(
          status: "delivered",
          last_http_status: resp.status,
          delivered_at: Time.current,
          updated_at: Time.current
        )
        :delivered
      else
        handle_failure(row, http_status: resp.status, error: "HTTP #{resp.status}")
      end
    rescue Faraday::Error => e
      handle_failure(row, http_status: nil, error: e.message)
    end

    def handle_failure(row, http_status:, error:)
      attempts = row["attempts"].to_i

      if attempts >= MAX_ATTEMPTS
        WebhookDelivery.where(id: row["id"]).update_all(
          status: "dead",
          last_http_status: http_status,
          last_error: error.to_s.truncate(500),
          updated_at: Time.current
        )
        @notifier.notify("<b>Webhook dead-lettered</b>\nDelivery ID: #{row['id']}\nURL: #{row['target_url']}\nError: #{error}")
        :dead
      else
        delay = (2**attempts) * 15
        WebhookDelivery.where(id: row["id"]).update_all(
          status: "pending",
          last_http_status: http_status,
          last_error: error.to_s.truncate(500),
          next_attempt_at: Time.current + delay.seconds,
          updated_at: Time.current
        )
        :retried
      end
    end
  end
end

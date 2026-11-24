# frozen_string_literal: true

require "rails_helper"

RSpec.describe Outbox::DispatchWebhooks do
  subject(:dispatcher) { described_class.new }

  let(:merchant) { create(:merchant, webhook_url: "https://merchant.example.test/hook") }
  let(:psp) { create(:psp_provider) }
  let(:payment) { create(:payment, merchant: merchant, psp_provider: psp, status: "captured") }

  it "delivers pending webhooks with HMAC signature and marks them delivered" do
    delivery = WebhookDelivery.create!(
      payment: payment, merchant: merchant, event_type: "payment.captured",
      target_url: merchant.webhook_url, payload: { payment_id: payment.id }, signature: "sig_abc",
      status: "pending", next_attempt_at: 1.second.ago
    )

    stub_request(:post, merchant.webhook_url)
      .with(headers: { "X-Paygate-Event" => "payment.captured", "X-Paygate-Signature" => "sig_abc" })
      .to_return(status: 200, body: "ok")

    summary = dispatcher.call(batch_size: 10)
    expect(summary).to eq({ delivered: 1, retried: 0, dead: 0 })
    expect(delivery.reload.status).to eq("delivered")
  end

  it "schedules exponential backoff on 500 and dead-letters on 5th failure" do
    delivery = WebhookDelivery.create!(
      payment: payment, merchant: merchant, event_type: "payment.captured",
      target_url: merchant.webhook_url, payload: { payment_id: payment.id }, signature: "sig_abc",
      status: "pending", attempts: 4, next_attempt_at: 1.second.ago
    )

    stub_request(:post, merchant.webhook_url).to_return(status: 500, body: "err")

    summary = dispatcher.call(batch_size: 10)
    expect(summary).to eq({ delivered: 0, retried: 0, dead: 1 })
    expect(delivery.reload.status).to eq("dead")
    expect(delivery.last_http_status).to eq(500)
  end
end

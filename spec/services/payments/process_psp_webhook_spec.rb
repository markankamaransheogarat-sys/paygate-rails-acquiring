# frozen_string_literal: true

require "rails_helper"

RSpec.describe Payments::ProcessPspWebhook do
  subject(:service) { described_class.new }

  let(:merchant) { create(:merchant, fee_bps: 300, rolling_reserve_bps: 200) }
  let(:psp) { create(:psp_provider, code: "asia_upi", region: "ASIA", supported_currencies: %w[INR], webhook_secret: "upi_secret") }
  let(:payment) { create(:payment, merchant: merchant, psp_provider: psp, amount_minor: 50_000, currency: "INR", region: "ASIA", status: "processing") }

  it "rejects invalid HMAC signature" do
    body = { payment_id: payment.id, psp_transaction_id: "tx_1", event: "captured" }.to_json
    res = service.call(provider_code: psp.code, raw_body: body, signature: "bad_sig", params: JSON.parse(body, symbolize_names: true))

    expect(res).to be_failure
    expect(res.failure.first).to eq(:invalid_signature)
  end

  it "captures async payment and processes subsequent chargeback" do
    capture_payload = { payment_id: payment.id, psp_transaction_id: "tx_upi_1", event: "captured" }
    capture_raw = capture_payload.to_json
    capture_sig = Security::HmacSigner.sign(secret: psp.webhook_secret, payload: capture_raw)

    res1 = service.call(provider_code: psp.code, raw_body: capture_raw, signature: capture_sig, params: capture_payload)
    expect(res1).to be_success
    expect(res1.value![:payment].status).to eq("captured")

    cb_payload = { payment_id: payment.id, psp_transaction_id: "tx_upi_1", event: "chargeback", failure_code: "fraud_dispute" }
    cb_raw = cb_payload.to_json
    cb_sig = Security::HmacSigner.sign(secret: psp.webhook_secret, payload: cb_raw)

    res2 = service.call(provider_code: psp.code, raw_body: cb_raw, signature: cb_sig, params: cb_payload)
    expect(res2).to be_success
    expect(res2.value![:payment].status).to eq("chargeback")
    expect(psp.reload.health_score.to_f).to be < 99.0
  end
end

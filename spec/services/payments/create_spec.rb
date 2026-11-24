# frozen_string_literal: true

require "rails_helper"

RSpec.describe Payments::Create do
  subject(:service) { described_class.new }

  let!(:merchant) { create(:merchant, fee_bps: 400, rolling_reserve_bps: 500) }
  let!(:primary_psp) { create(:psp_provider, code: "psp_primary", region: "CIS", priority: 10, health_score: 99.0) }
  let!(:backup_psp) { create(:psp_provider, code: "psp_backup", region: "CIS", priority: 20, health_score: 95.0) }

  let(:params) do
    {
      idempotency_key: "idem_order_9001",
      external_order_id: "order-9001",
      amount_minor: 100_000,
      currency: "RUB",
      payment_method: "card",
      region: "CIS"
    }
  end

  it "fails over to backup PSP when primary returns 503 and posts double-entry ledger" do
    stub_request(:post, "https://psp-sandbox.internal/v1/providers/psp_primary/charges")
      .to_return(status: 503, body: { code: "upstream_timeout", message: "Gateway busy", retryable: true }.to_json, headers: { "Content-Type" => "application/json" })

    stub_request(:post, "https://psp-sandbox.internal/v1/providers/psp_backup/charges")
      .to_return(status: 200, body: { status: "captured", transaction_id: "tx_backup_777" }.to_json, headers: { "Content-Type" => "application/json" })

    result = service.call(merchant: merchant, params: params)

    expect(result).to be_success
    payment = result.value![:payment]
    expect(payment.status).to eq("captured")
    expect(payment.psp_provider_id).to eq(backup_psp.id)
    expect(payment.cascade_attempts).to eq(2)
    expect(payment.cascade_trace.map { |t| t["psp"] }).to eq(%w[psp_primary psp_backup])

    # 100_000 gross - 4% fee (4_000) - 5% reserve (5_000) = 91_000 available
    balances = Queries::Ledger::MerchantBalanceQuery.call(merchant_id: merchant.id)
    available = balances.find { |b| b["account_type"] == "available" }
    reserve = balances.find { |b| b["account_type"] == "reserve" }

    expect(available["balance_minor"]).to eq(91_000)
    expect(available["journal_net_minor"]).to eq(91_000)
    expect(reserve["balance_minor"]).to eq(5_000)
    expect(WebhookDelivery.where(payment: payment, event_type: "payment.captured").count).to eq(1)
  end

  it "stops cascade immediately on hard non-retryable decline" do
    stub_request(:post, "https://psp-sandbox.internal/v1/providers/psp_primary/charges")
      .to_return(status: 402, body: { code: "stolen_card", message: "Fraud rule", retryable: false }.to_json, headers: { "Content-Type" => "application/json" })

    result = service.call(merchant: merchant, params: params)

    expect(result).to be_success
    payment = result.value![:payment]
    expect(payment.status).to eq("failed")
    expect(payment.cascade_attempts).to eq(1)
    expect(payment.failure_code).to eq("stolen_card")
    expect(WebhookDelivery.where(payment: payment, event_type: "payment.failed").count).to eq(1)
  end

  it "replays existing payment without re-charging on duplicate idempotency_key" do
    stub_request(:post, "https://psp-sandbox.internal/v1/providers/psp_primary/charges")
      .to_return(status: 200, body: { status: "captured", transaction_id: "tx_once_1" }.to_json, headers: { "Content-Type" => "application/json" })

    first = service.call(merchant: merchant, params: params)
    second = service.call(merchant: merchant, params: params)

    expect(first.value![:idempotent_replay]).to be(false)
    expect(second.value![:idempotent_replay]).to be(true)
    expect(second.value![:payment].id).to eq(first.value![:payment].id)
    expect(WebMock).to have_requested(:post, "https://psp-sandbox.internal/v1/providers/psp_primary/charges").once
  end
end

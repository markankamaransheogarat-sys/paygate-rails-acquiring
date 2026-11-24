# frozen_string_literal: true

require "rails_helper"

RSpec.describe "PostgreSQL Raw SQL Queries" do
  describe Queries::Outbox::ClaimDueWebhooksQuery do
    it "claims due pending webhooks once using SKIP LOCKED semantics" do
      merchant = create(:merchant)
      psp = create(:psp_provider)
      payment = create(:payment, merchant: merchant, psp_provider: psp, status: "captured")

      due = WebhookDelivery.create!(
        payment: payment, merchant: merchant, event_type: "payment.captured",
        target_url: merchant.webhook_url, payload: { ok: true }, signature: "sig",
        status: "pending", next_attempt_at: 1.minute.ago
      )
      WebhookDelivery.create!(
        payment: payment, merchant: merchant, event_type: "payment.captured",
        target_url: merchant.webhook_url, payload: { ok: true }, signature: "sig",
        status: "pending", next_attempt_at: 10.minutes.from_now
      )

      claimed_first = described_class.call(limit: 10)
      claimed_second = described_class.call(limit: 10)

      expect(claimed_first.map { |r| r["id"] }).to eq([ due.id ])
      expect(claimed_second).to be_empty
      expect(due.reload.status).to eq("processing")
      expect(due.attempts).to eq(1)
    end
  end

  describe Queries::Analytics::MerchantTurnoverQuery do
    it "computes conversion rate, cascade recovery, and P95 ticket in SQL CTE" do
      merchant = create(:merchant)
      psp = create(:psp_provider, code: "kz_kaspi", region: "CIS", supported_currencies: %w[KZT])

      create(:payment, merchant: merchant, psp_provider: psp, currency: "KZT", region: "CIS", amount_minor: 10_000, status: "captured", cascade_attempts: 1)
      create(:payment, merchant: merchant, psp_provider: psp, currency: "KZT", region: "CIS", amount_minor: 50_000, status: "captured", cascade_attempts: 2)
      create(:payment, merchant: merchant, psp_provider: psp, currency: "KZT", region: "CIS", amount_minor: 20_000, status: "failed", cascade_attempts: 2)

      rows = described_class.call(since: 1.hour.ago, merchant_id: merchant.id)
      expect(rows.size).to eq(1)
      row = rows.first
      expect(row["total_count"]).to eq(3)
      expect(row["success_count"]).to eq(2)
      expect(row["cascade_recovered_count"]).to eq(1)
      expect(row["gross_captured_minor"]).to eq(60_000)
      expect(row["conversion_pct"].to_f).to eq(66.67)
    end
  end
end

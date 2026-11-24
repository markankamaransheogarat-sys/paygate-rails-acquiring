# frozen_string_literal: true

require "rails_helper"

RSpec.describe Payments::IssueRefund do
  subject(:service) { described_class.new }

  let(:merchant) { create(:merchant, fee_bps: 300, rolling_reserve_bps: 500) }
  let(:psp) { create(:psp_provider) }
  let(:payment) { create(:payment, merchant: merchant, psp_provider: psp, amount_minor: 100_000, status: "captured") }

  before do
    Ledger::PostEntry.new.record_capture_settlement!(payment: payment, merchant: merchant)
  end

  it "supports partial and final refunds while updating ledger balances atomically" do
    first = service.call(merchant: merchant, params: { payment_id: payment.id, amount_minor: 40_000, idempotency_key: "refund_key_1", reason: "partial" })
    expect(first).to be_success
    expect(first.value![:payment].status).to eq("partially_refunded")
    expect(first.value![:payment].refunded_amount_minor).to eq(40_000)

    over = service.call(merchant: merchant, params: { payment_id: payment.id, amount_minor: 70_000, idempotency_key: "refund_key_over" })
    expect(over).to be_failure
    expect(over.failure.first).to eq(:amount_exceeds_refundable)

    second = service.call(merchant: merchant, params: { payment_id: payment.id, amount_minor: 50_000, idempotency_key: "refund_key_2" })
    expect(second).to be_success
    expect(second.value![:payment].refunded_amount_minor).to eq(90_000)

    # Available started at 92_000 (100k - 3k fee - 5k reserve), refunded 90_000 => 2_000 left;
    # Trying to refund remaining 10_000 should fail due to insufficient available balance.
    insufficient = service.call(merchant: merchant, params: { payment_id: payment.id, amount_minor: 10_000, idempotency_key: "refund_key_3" })
    expect(insufficient).to be_failure
    expect(insufficient.failure.first).to eq(:insufficient_funds)
  end
end

# frozen_string_literal: true

require "rails_helper"

RSpec.describe Contracts::Payments::CreateContract do
  subject(:contract) { described_class.new }

  let(:valid_params) do
    {
      idempotency_key: "idem_12345678",
      external_order_id: "order-42",
      amount_minor: 250_000,
      currency: "RUB",
      payment_method: "card",
      region: "CIS"
    }
  end

  it "accepts valid CIS payment payload" do
    expect(contract.call(valid_params)).to be_success
  end

  it "rejects mismatched region and currency (INR on CIS)" do
    result = contract.call(valid_params.merge(currency: "INR", region: "CIS"))
    expect(result).to be_failure
    expect(result.errors.to_h[:currency]).to include("is not supported for CIS acquiring")
  end

  it "rejects non-positive amount_minor" do
    result = contract.call(valid_params.merge(amount_minor: 0))
    expect(result).to be_failure
    expect(result.errors.to_h[:amount_minor]).to be_present
  end
end

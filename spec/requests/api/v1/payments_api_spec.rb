# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Grape API v1", type: :request do
  let!(:merchant) { create(:merchant, code: "m_api_1", api_key: "pk_api_1", api_secret: "sk_api_secret_1") }
  let!(:psp) { create(:psp_provider, code: "cis_alfa", region: "CIS", supported_currencies: %w[RUB]) }

  def signed_headers(body_str, extra = {})
    ts = Time.now.to_i.to_s
    sig = Security::HmacSigner.sign(secret: merchant.api_secret, payload: body_str, timestamp: ts)
    {
      "CONTENT_TYPE" => "application/json",
      "X-Merchant-Key" => merchant.api_key,
      "X-Timestamp" => ts,
      "X-Signature" => sig
    }.merge(extra)
  end

  it "creates, fetches, refunds payment and returns verified balance" do
    stub_request(:post, "https://psp-sandbox.internal/v1/providers/cis_alfa/charges")
      .to_return(status: 200, body: { status: "captured", transaction_id: "tx_api_100" }.to_json, headers: { "Content-Type" => "application/json" })

    create_body = {
      idempotency_key: "idem_api_100",
      external_order_id: "ord_api_100",
      amount_minor: 200_000,
      currency: "RUB",
      payment_method: "card",
      region: "CIS"
    }.to_json

    post "/api/v1/payments", params: create_body, headers: signed_headers(create_body)
    expect(response).to have_http_status(:created)

    json = JSON.parse(response.body)
    payment_id = json.dig("payment", "id")
    expect(json.dig("payment", "status")).to eq("captured")

    get "/api/v1/payments/#{payment_id}", headers: signed_headers("")
    expect(response).to have_http_status(:ok)
    expect(JSON.parse(response.body).dig("payment", "psp_code")).to eq("cis_alfa")

    refund_body = { amount_minor: 50_000, idempotency_key: "ref_api_1" }.to_json
    post "/api/v1/payments/#{payment_id}/refunds", params: refund_body, headers: signed_headers(refund_body)
    expect(response).to have_http_status(:created)
    expect(JSON.parse(response.body).dig("payment", "status")).to eq("partially_refunded")

    get "/api/v1/merchants/balance", headers: signed_headers("")
    expect(response).to have_http_status(:ok)
    balances = JSON.parse(response.body)["balances"]
    available = balances.find { |b| b["account_type"] == "available" }
    # 200_000 - 7_000 (3.5% fee) - 10_000 (5% reserve) - 50_000 (refund) = 133_000
    expect(available["balance_minor"]).to eq(133_000)
  end

  it "rejects unsigned requests with 401" do
    post "/api/v1/payments", params: {}.to_json, headers: { "CONTENT_TYPE" => "application/json" }
    expect(response).to have_http_status(:unauthorized)
  end

  it "handles Telegram bot commands and Admin dashboard" do
    post "/api/v1/webhooks/telegram",
         params: { message: { text: "/stuck" } }.to_json,
         headers: { "CONTENT_TYPE" => "application/json", "X-Telegram-Bot-Api-Secret-Token" => "dev-tg-secret" }
    expect(response).to have_http_status(:ok)
    expect(JSON.parse(response.body)["reply"]).to include("Stuck processing payments")

    get "/admin"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("PayGate Acquiring Core")
  end
end

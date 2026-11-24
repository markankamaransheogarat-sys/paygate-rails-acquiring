# frozen_string_literal: true

puts "Seeding PSP providers (CIS & Asia)..."

psps = [
  {
    code: "cis_card_alfa",
    name: "Alfa CIS High-Risk Card Gateway",
    region: "CIS",
    supported_currencies: %w[RUB KZT USD],
    priority: 10,
    cost_bps: 190,
    min_amount_minor: 10_000,
    max_amount_minor: 50_000_000,
    webhook_secret: "psp_secret_cis_card_alfa",
    health_score: 98.5
  },
  {
    code: "kz_p2p_kaspi",
    name: "Kaspi P2P & Card Cascade",
    region: "CIS",
    supported_currencies: %w[KZT RUB UZS],
    priority: 20,
    cost_bps: 210,
    min_amount_minor: 5000,
    max_amount_minor: 30_000_000,
    webhook_secret: "psp_secret_kz_p2p_kaspi",
    health_score: 96.0
  },
  {
    code: "asia_upi_pay",
    name: "India UPI Instant Acquiring",
    region: "ASIA",
    supported_currencies: %w[INR USD],
    priority: 10,
    cost_bps: 240,
    min_amount_minor: 10_000,
    max_amount_minor: 20_000_000,
    webhook_secret: "psp_secret_asia_upi_pay",
    health_score: 97.2
  },
  {
    code: "asia_thb_qr",
    name: "Thailand PromptPay QR Gateway",
    region: "ASIA",
    supported_currencies: %w[THB USD],
    priority: 15,
    cost_bps: 220,
    min_amount_minor: 10_000,
    max_amount_minor: 25_000_000,
    webhook_secret: "psp_secret_asia_thb_qr",
    health_score: 95.8
  }
]

psps.each do |attrs|
  PspProvider.find_or_create_by!(code: attrs[:code]) do |p|
    p.assign_attributes(attrs)
  end
end

puts "Seeding merchants..."

Merchant.find_or_create_by!(code: "m_cis_gaming_01") do |m|
  m.name = "CIS Gaming Platform"
  m.api_key = "pk_live_cis_gaming_01"
  m.api_secret = "sk_live_cis_gaming_secret_01"
  m.webhook_url = "https://merchant.example.com/webhooks/paygate"
  m.fee_bps = 350
  m.rolling_reserve_bps = 500
  m.custom_routing_rules = { "preferred_psp" => "cis_card_alfa" }
end

puts "Done."

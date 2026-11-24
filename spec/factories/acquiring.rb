# frozen_string_literal: true

FactoryBot.define do
  factory :merchant do
    sequence(:code) { |n| "m_test_#{n}" }
    name { "Test High-Risk Merchant" }
    sequence(:api_key) { |n| "pk_test_#{n}" }
    api_secret { "sk_test_secret_123456" }
    webhook_url { "https://merchant.example.test/webhooks" }
    fee_bps { 350 }
    rolling_reserve_bps { 500 }
    custom_routing_rules { {} }
    active { true }
  end

  factory :psp_provider do
    sequence(:code) { |n| "psp_#{n}" }
    name { "Test PSP" }
    region { "CIS" }
    supported_currencies { %w[RUB KZT USD] }
    priority { 10 }
    cost_bps { 180 }
    min_amount_minor { 100 }
    max_amount_minor { 50_000_000 }
    webhook_secret { "psp_webhook_secret_123" }
    health_score { 99.0 }
    active { true }
  end

  factory :payment do
    association :merchant
    association :psp_provider
    sequence(:idempotency_key) { |n| "idem_key_#{n}_#{SecureRandom.hex(4)}" }
    sequence(:external_order_id) { |n| "ord_#{n}" }
    amount_minor { 100_000 }
    refunded_amount_minor { 0 }
    currency { "RUB" }
    payment_method { "card" }
    region { "CIS" }
    status { "processing" }
  end
end

# frozen_string_literal: true

class CreateAcquiringCore < ActiveRecord::Migration[7.2]
  def change
    enable_extension "pgcrypto" unless extension_enabled?("pgcrypto")

    create_table :merchants do |t|
      t.string :code, null: false
      t.string :name, null: false
      t.string :api_key, null: false
      t.string :api_secret, null: false
      t.string :webhook_url
      t.integer :fee_bps, null: false, default: 350
      t.integer :rolling_reserve_bps, null: false, default: 500
      t.jsonb :custom_routing_rules, null: false, default: {}
      t.boolean :active, null: false, default: true
      t.timestamps
    end

    add_index :merchants, :code, unique: true
    add_index :merchants, :api_key, unique: true
    add_check_constraint :merchants, "fee_bps >= 0 AND fee_bps <= 5000", name: "chk_merchants_fee_bps"
    add_check_constraint :merchants, "rolling_reserve_bps >= 0 AND rolling_reserve_bps <= 5000", name: "chk_merchants_reserve_bps"

    create_table :psp_providers do |t|
      t.string :code, null: false
      t.string :name, null: false
      t.string :region, null: false
      t.string :supported_currencies, array: true, null: false, default: []
      t.integer :priority, null: false, default: 100
      t.integer :cost_bps, null: false, default: 180
      t.bigint :min_amount_minor, null: false, default: 100
      t.bigint :max_amount_minor, null: false, default: 100_000_000
      t.string :webhook_secret, null: false
      t.decimal :health_score, precision: 5, scale: 2, null: false, default: 100.0
      t.boolean :active, null: false, default: true
      t.timestamps
    end

    add_index :psp_providers, :code, unique: true
    add_index :psp_providers, %i[active region priority]
    add_index :psp_providers, :supported_currencies, using: :gin

    create_table :payments, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :merchant, null: false, foreign_key: true
      t.references :psp_provider, null: true, foreign_key: true
      t.string :idempotency_key, null: false
      t.string :external_order_id, null: false
      t.string :psp_transaction_id
      t.bigint :amount_minor, null: false
      t.bigint :refunded_amount_minor, null: false, default: 0
      t.string :currency, limit: 3, null: false
      t.string :payment_method, null: false
      t.string :region, null: false
      t.string :status, null: false, default: "pending"
      t.integer :cascade_attempts, null: false, default: 0
      t.jsonb :cascade_trace, null: false, default: []
      t.string :failure_code
      t.string :failure_reason
      t.jsonb :customer_payload, null: false, default: {}
      t.datetime :captured_at
      t.timestamps
    end

    add_index :payments, %i[merchant_id idempotency_key], unique: true
    add_index :payments, %i[psp_provider_id psp_transaction_id],
              unique: true,
              where: "psp_transaction_id IS NOT NULL",
              name: "idx_payments_psp_tx_unique"
    add_index :payments, %i[status created_at]
    add_index :payments, %i[merchant_id created_at]
    add_check_constraint :payments, "amount_minor > 0", name: "chk_payments_amount_positive"
    add_check_constraint :payments, "refunded_amount_minor >= 0 AND refunded_amount_minor <= amount_minor",
                         name: "chk_payments_refunded_bounds"

    create_table :ledger_accounts do |t|
      t.references :merchant, null: true, foreign_key: true
      t.string :currency, limit: 3, null: false
      t.string :account_type, null: false
      t.bigint :balance_minor, null: false, default: 0
      t.timestamps
    end

    add_index :ledger_accounts, %i[merchant_id currency account_type],
              unique: true,
              where: "merchant_id IS NOT NULL",
              name: "idx_ledger_accounts_merchant_unique"
    add_index :ledger_accounts, %i[currency account_type],
              unique: true,
              where: "merchant_id IS NULL",
              name: "idx_ledger_accounts_platform_unique"

    create_table :ledger_entries do |t|
      t.references :payment, type: :uuid, null: false, foreign_key: true
      t.references :debit_account, null: false, foreign_key: { to_table: :ledger_accounts }
      t.references :credit_account, null: false, foreign_key: { to_table: :ledger_accounts }
      t.bigint :amount_minor, null: false
      t.string :currency, limit: 3, null: false
      t.string :entry_kind, null: false
      t.string :idempotency_key, null: false
      t.jsonb :metadata, null: false, default: {}
      t.datetime :created_at, null: false, default: -> { "CURRENT_TIMESTAMP" }
    end

    add_index :ledger_entries, :idempotency_key, unique: true
    add_index :ledger_entries, %i[entry_kind created_at]
    add_check_constraint :ledger_entries, "amount_minor > 0", name: "chk_ledger_entries_positive"
    add_check_constraint :ledger_entries, "debit_account_id <> credit_account_id", name: "chk_ledger_entries_distinct_accounts"

    create_table :webhook_deliveries do |t|
      t.references :payment, type: :uuid, null: false, foreign_key: true
      t.references :merchant, null: false, foreign_key: true
      t.string :event_type, null: false
      t.string :target_url, null: false
      t.jsonb :payload, null: false, default: {}
      t.string :signature, null: false
      t.string :status, null: false, default: "pending"
      t.integer :attempts, null: false, default: 0
      t.datetime :next_attempt_at, null: false, default: -> { "CURRENT_TIMESTAMP" }
      t.integer :last_http_status
      t.text :last_error
      t.datetime :delivered_at
      t.timestamps
    end

    add_index :webhook_deliveries, :next_attempt_at,
              where: "status IN ('pending', 'processing')",
              name: "idx_webhook_deliveries_due"
  end
end

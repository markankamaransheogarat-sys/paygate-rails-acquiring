# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[7.2].define(version: 2026_11_24_000001) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pgcrypto"
  enable_extension "plpgsql"

  create_table "ledger_accounts", force: :cascade do |t|
    t.bigint "merchant_id"
    t.string "currency", limit: 3, null: false
    t.string "account_type", null: false
    t.bigint "balance_minor", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["currency", "account_type"], name: "idx_ledger_accounts_platform_unique", unique: true, where: "(merchant_id IS NULL)"
    t.index ["merchant_id", "currency", "account_type"], name: "idx_ledger_accounts_merchant_unique", unique: true, where: "(merchant_id IS NOT NULL)"
    t.index ["merchant_id"], name: "index_ledger_accounts_on_merchant_id"
  end

  create_table "ledger_entries", force: :cascade do |t|
    t.uuid "payment_id", null: false
    t.bigint "debit_account_id", null: false
    t.bigint "credit_account_id", null: false
    t.bigint "amount_minor", null: false
    t.string "currency", limit: 3, null: false
    t.string "entry_kind", null: false
    t.string "idempotency_key", null: false
    t.jsonb "metadata", default: {}, null: false
    t.datetime "created_at", default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.index ["credit_account_id"], name: "index_ledger_entries_on_credit_account_id"
    t.index ["debit_account_id"], name: "index_ledger_entries_on_debit_account_id"
    t.index ["entry_kind", "created_at"], name: "index_ledger_entries_on_entry_kind_and_created_at"
    t.index ["idempotency_key"], name: "index_ledger_entries_on_idempotency_key", unique: true
    t.index ["payment_id"], name: "index_ledger_entries_on_payment_id"
    t.check_constraint "amount_minor > 0", name: "chk_ledger_entries_positive"
    t.check_constraint "debit_account_id <> credit_account_id", name: "chk_ledger_entries_distinct_accounts"
  end

  create_table "merchants", force: :cascade do |t|
    t.string "code", null: false
    t.string "name", null: false
    t.string "api_key", null: false
    t.string "api_secret", null: false
    t.string "webhook_url"
    t.integer "fee_bps", default: 350, null: false
    t.integer "rolling_reserve_bps", default: 500, null: false
    t.jsonb "custom_routing_rules", default: {}, null: false
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["api_key"], name: "index_merchants_on_api_key", unique: true
    t.index ["code"], name: "index_merchants_on_code", unique: true
    t.check_constraint "fee_bps >= 0 AND fee_bps <= 5000", name: "chk_merchants_fee_bps"
    t.check_constraint "rolling_reserve_bps >= 0 AND rolling_reserve_bps <= 5000", name: "chk_merchants_reserve_bps"
  end

  create_table "payments", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.bigint "merchant_id", null: false
    t.bigint "psp_provider_id"
    t.string "idempotency_key", null: false
    t.string "external_order_id", null: false
    t.string "psp_transaction_id"
    t.bigint "amount_minor", null: false
    t.bigint "refunded_amount_minor", default: 0, null: false
    t.string "currency", limit: 3, null: false
    t.string "payment_method", null: false
    t.string "region", null: false
    t.string "status", default: "pending", null: false
    t.integer "cascade_attempts", default: 0, null: false
    t.jsonb "cascade_trace", default: [], null: false
    t.string "failure_code"
    t.string "failure_reason"
    t.jsonb "customer_payload", default: {}, null: false
    t.datetime "captured_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["merchant_id", "created_at"], name: "index_payments_on_merchant_id_and_created_at"
    t.index ["merchant_id", "idempotency_key"], name: "index_payments_on_merchant_id_and_idempotency_key", unique: true
    t.index ["merchant_id"], name: "index_payments_on_merchant_id"
    t.index ["psp_provider_id", "psp_transaction_id"], name: "idx_payments_psp_tx_unique", unique: true, where: "(psp_transaction_id IS NOT NULL)"
    t.index ["psp_provider_id"], name: "index_payments_on_psp_provider_id"
    t.index ["status", "created_at"], name: "index_payments_on_status_and_created_at"
    t.check_constraint "amount_minor > 0", name: "chk_payments_amount_positive"
    t.check_constraint "refunded_amount_minor >= 0 AND refunded_amount_minor <= amount_minor", name: "chk_payments_refunded_bounds"
  end

  create_table "psp_providers", force: :cascade do |t|
    t.string "code", null: false
    t.string "name", null: false
    t.string "region", null: false
    t.string "supported_currencies", default: [], null: false, array: true
    t.integer "priority", default: 100, null: false
    t.integer "cost_bps", default: 180, null: false
    t.bigint "min_amount_minor", default: 100, null: false
    t.bigint "max_amount_minor", default: 100000000, null: false
    t.string "webhook_secret", null: false
    t.decimal "health_score", precision: 5, scale: 2, default: "100.0", null: false
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["active", "region", "priority"], name: "index_psp_providers_on_active_and_region_and_priority"
    t.index ["code"], name: "index_psp_providers_on_code", unique: true
    t.index ["supported_currencies"], name: "index_psp_providers_on_supported_currencies", using: :gin
  end

  create_table "webhook_deliveries", force: :cascade do |t|
    t.uuid "payment_id", null: false
    t.bigint "merchant_id", null: false
    t.string "event_type", null: false
    t.string "target_url", null: false
    t.jsonb "payload", default: {}, null: false
    t.string "signature", null: false
    t.string "status", default: "pending", null: false
    t.integer "attempts", default: 0, null: false
    t.datetime "next_attempt_at", default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.integer "last_http_status"
    t.text "last_error"
    t.datetime "delivered_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["merchant_id"], name: "index_webhook_deliveries_on_merchant_id"
    t.index ["next_attempt_at"], name: "idx_webhook_deliveries_due", where: "((status)::text = ANY ((ARRAY['pending'::character varying, 'processing'::character varying])::text[]))"
    t.index ["payment_id"], name: "index_webhook_deliveries_on_payment_id"
  end

  add_foreign_key "ledger_accounts", "merchants"
  add_foreign_key "ledger_entries", "ledger_accounts", column: "credit_account_id"
  add_foreign_key "ledger_entries", "ledger_accounts", column: "debit_account_id"
  add_foreign_key "ledger_entries", "payments"
  add_foreign_key "payments", "merchants"
  add_foreign_key "payments", "psp_providers"
  add_foreign_key "webhook_deliveries", "merchants"
  add_foreign_key "webhook_deliveries", "payments"
end

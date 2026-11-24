# frozen_string_literal: true

module Ledger
  class PostEntry
    include Dry::Monads[:result]

    LOCK_ACCOUNTS_SQL = <<~SQL.squish
      SELECT id, balance_minor, account_type
      FROM ledger_accounts
      WHERE id IN (:ids)
      ORDER BY id ASC
      FOR UPDATE
    SQL

    UPDATE_BALANCE_SQL = <<~SQL.squish
      UPDATE ledger_accounts
      SET balance_minor = balance_minor + :delta,
          updated_at = NOW()
      WHERE id = :id
    SQL

    INSERT_ENTRY_SQL = <<~SQL.squish
      INSERT INTO ledger_entries (
        payment_id,
        debit_account_id,
        credit_account_id,
        amount_minor,
        currency,
        entry_kind,
        idempotency_key,
        metadata,
        created_at
      )
      VALUES (
        :payment_id,
        :debit_account_id,
        :credit_account_id,
        :amount_minor,
        :currency,
        :entry_kind,
        :idempotency_key,
        CAST(:metadata AS jsonb),
        NOW()
      )
      ON CONFLICT (idempotency_key) DO NOTHING
      RETURNING id
    SQL

    def self.ensure_account!(merchant_id:, currency:, account_type:)
      LedgerAccount.find_or_create_by!(
        merchant_id: merchant_id,
        currency: currency,
        account_type: account_type
      )
    rescue ActiveRecord::RecordNotUnique
      LedgerAccount.find_by!(
        merchant_id: merchant_id,
        currency: currency,
        account_type: account_type
      )
    end

    def call(payment:, debit_account:, credit_account:, amount_minor:, entry_kind:, idempotency_key:, enforce_non_negative_debit: false, metadata: {})
      return Failure([ :invalid_amount, "Amount must be positive" ]) if amount_minor.to_i <= 0
      return Failure([ :same_account, "Debit and credit accounts must differ" ]) if debit_account.id == credit_account.id

      ActiveRecord::Base.transaction(requires_new: true) do
        locked = lock_accounts([ debit_account.id, credit_account.id ])
        debit_row = locked.fetch(debit_account.id)

        if enforce_non_negative_debit && debit_row.fetch("balance_minor").to_i < amount_minor
          raise ActiveRecord::Rollback
        end

        inserted = execute_insert(
          payment_id: payment.id,
          debit_account_id: debit_account.id,
          credit_account_id: credit_account.id,
          amount_minor: amount_minor,
          currency: payment.currency,
          entry_kind: entry_kind,
          idempotency_key: idempotency_key,
          metadata: metadata.to_json
        )

        if inserted.any?
          execute_balance_delta(id: debit_account.id, delta: -amount_minor)
          execute_balance_delta(id: credit_account.id, delta: amount_minor)
          Success(entry_id: inserted.first.fetch("id"), replayed: false)
        else
          Success(entry_id: nil, replayed: true)
        end
      end || Failure([ :insufficient_funds, "Insufficient balance on account #{debit_account.id}" ])
    end

    def record_capture_settlement!(payment:, merchant:)
      clearing = self.class.ensure_account!(merchant_id: nil, currency: payment.currency, account_type: "psp_clearing")
      available = self.class.ensure_account!(merchant_id: merchant.id, currency: payment.currency, account_type: "available")
      reserve = self.class.ensure_account!(merchant_id: merchant.id, currency: payment.currency, account_type: "reserve")
      revenue = self.class.ensure_account!(merchant_id: nil, currency: payment.currency, account_type: "fee_revenue")

      fee_minor = (payment.amount_minor * merchant.fee_bps) / 10_000
      reserve_minor = (payment.amount_minor * merchant.rolling_reserve_bps) / 10_000

      call(
        payment: payment,
        debit_account: clearing,
        credit_account: available,
        amount_minor: payment.amount_minor,
        entry_kind: "capture_gross",
        idempotency_key: "capture_gross:#{payment.id}"
      )

      if fee_minor.positive?
        call(
          payment: payment,
          debit_account: available,
          credit_account: revenue,
          amount_minor: fee_minor,
          entry_kind: "merchant_fee",
          idempotency_key: "merchant_fee:#{payment.id}",
          metadata: { fee_bps: merchant.fee_bps }
        )
      end

      if reserve_minor.positive?
        call(
          payment: payment,
          debit_account: available,
          credit_account: reserve,
          amount_minor: reserve_minor,
          entry_kind: "rolling_reserve",
          idempotency_key: "rolling_reserve:#{payment.id}",
          metadata: { rolling_reserve_bps: merchant.rolling_reserve_bps }
        )
      end

      Success(gross: payment.amount_minor, fee: fee_minor, reserve: reserve_minor)
    end

    private

    def lock_accounts(ids)
      sql = ActiveRecord::Base.sanitize_sql_array([ LOCK_ACCOUNTS_SQL, { ids: ids } ])
      rows = ActiveRecord::Base.connection.exec_query(sql).to_a
      rows.index_by { |r| r.fetch("id").to_i }
    end

    def execute_balance_delta(id:, delta:)
      sql = ActiveRecord::Base.sanitize_sql_array([ UPDATE_BALANCE_SQL, { id: id, delta: delta } ])
      ActiveRecord::Base.connection.exec_update(sql)
    end

    def execute_insert(params)
      sql = ActiveRecord::Base.sanitize_sql_array([ INSERT_ENTRY_SQL, params ])
      ActiveRecord::Base.connection.exec_query(sql).to_a
    end
  end
end

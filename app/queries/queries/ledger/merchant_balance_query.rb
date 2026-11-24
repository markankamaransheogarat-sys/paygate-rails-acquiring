# frozen_string_literal: true

module Queries
  module Ledger
    class MerchantBalanceQuery
      SQL = <<~SQL.squish
        SELECT
          la.currency,
          la.account_type,
          la.balance_minor::bigint AS balance_minor,
          (
            COALESCE((SELECT SUM(le.amount_minor) FROM ledger_entries le WHERE le.credit_account_id = la.id), 0) -
            COALESCE((SELECT SUM(le.amount_minor) FROM ledger_entries le WHERE le.debit_account_id = la.id), 0)
          )::bigint AS journal_net_minor
        FROM ledger_accounts la
        WHERE la.merchant_id = :merchant_id
        ORDER BY la.currency ASC, la.account_type ASC
      SQL

      def self.call(merchant_id:)
        sanitized = ActiveRecord::Base.sanitize_sql_array([ SQL, { merchant_id: merchant_id } ])
        ActiveRecord::Base.connection.exec_query(sanitized).to_a
      end
    end
  end
end

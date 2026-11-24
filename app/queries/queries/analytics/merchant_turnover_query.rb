# frozen_string_literal: true

module Queries
  module Analytics
    class MerchantTurnoverQuery
      SQL = <<~SQL.squish
        WITH scoped_payments AS (
          SELECT
            p.merchant_id,
            p.currency,
            p.region,
            p.status,
            p.amount_minor,
            p.refunded_amount_minor,
            p.cascade_attempts,
            psp.code AS psp_code
          FROM payments p
          LEFT JOIN psp_providers psp ON psp.id = p.psp_provider_id
          WHERE p.created_at >= :since
            AND (:merchant_id IS NULL OR p.merchant_id = :merchant_id)
        )
        SELECT
          currency,
          region,
          COALESCE(psp_code, 'unassigned') AS psp_code,
          COUNT(*) AS total_count,
          COUNT(*) FILTER (WHERE status IN ('captured', 'partially_refunded', 'refunded')) AS success_count,
          COUNT(*) FILTER (WHERE status = 'captured' AND cascade_attempts > 1) AS cascade_recovered_count,
          COUNT(*) FILTER (WHERE status = 'chargeback') AS chargeback_count,
          COALESCE(SUM(amount_minor) FILTER (WHERE status IN ('captured', 'partially_refunded', 'refunded')), 0)::bigint AS gross_captured_minor,
          COALESCE(SUM(refunded_amount_minor), 0)::bigint AS total_refunded_minor,
          ROUND(
            100.0 * COUNT(*) FILTER (WHERE status IN ('captured', 'partially_refunded', 'refunded')) / NULLIF(COUNT(*), 0),
            2
          ) AS conversion_pct,
          COALESCE(
            PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY amount_minor)::bigint,
            0
          ) AS p95_ticket_minor
        FROM scoped_payments
        GROUP BY currency, region, COALESCE(psp_code, 'unassigned')
        ORDER BY gross_captured_minor DESC, total_count DESC
      SQL

      def self.call(since: 24.hours.ago, merchant_id: nil)
        sanitized = ActiveRecord::Base.sanitize_sql_array([
          SQL,
          { since: since, merchant_id: merchant_id }
        ])

        ActiveRecord::Base.connection.exec_query(sanitized).to_a
      end
    end
  end
end

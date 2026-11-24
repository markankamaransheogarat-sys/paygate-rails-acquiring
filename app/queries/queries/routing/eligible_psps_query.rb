# frozen_string_literal: true

module Queries
  module Routing
    class EligiblePspsQuery
      SQL = <<~SQL.squish
        SELECT
          id,
          code,
          name,
          region,
          priority,
          cost_bps,
          health_score,
          webhook_secret
        FROM psp_providers
        WHERE active = TRUE
          AND (region = :region OR region = 'GLOBAL')
          AND :currency = ANY(supported_currencies)
          AND :amount_minor BETWEEN min_amount_minor AND max_amount_minor
          AND NOT (code = ANY(:excluded_codes))
        ORDER BY
          CASE WHEN code = :preferred_code THEN 0 ELSE 1 END ASC,
          health_score DESC,
          priority ASC,
          cost_bps ASC
      SQL

      def self.call(region:, currency:, amount_minor:, preferred_code: nil, excluded_codes: [])
        sanitized = ActiveRecord::Base.sanitize_sql_array([
          SQL,
          {
            region: region,
            currency: currency,
            amount_minor: amount_minor,
            preferred_code: preferred_code.to_s,
            excluded_codes: "{#{Array(excluded_codes).map { |c| c.to_s.gsub(/[^a-zA-Z0-9_-]/, '') }.join(',')}}"
          }
        ])

        ActiveRecord::Base.connection.exec_query(sanitized).to_a
      end
    end
  end
end

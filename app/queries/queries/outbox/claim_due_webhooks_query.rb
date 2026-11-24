# frozen_string_literal: true

module Queries
  module Outbox
    class ClaimDueWebhooksQuery
      SQL = <<~SQL.squish
        WITH due AS (
          SELECT id
          FROM webhook_deliveries
          WHERE status = 'pending'
            AND next_attempt_at <= NOW()
          ORDER BY next_attempt_at ASC
          LIMIT :limit
          FOR UPDATE SKIP LOCKED
        )
        UPDATE webhook_deliveries wd
        SET
          status = 'processing',
          attempts = wd.attempts + 1,
          updated_at = NOW()
        FROM due
        WHERE wd.id = due.id
        RETURNING wd.*
      SQL

      def self.call(limit: 25)
        sanitized = ActiveRecord::Base.sanitize_sql_array([ SQL, { limit: limit } ])
        ActiveRecord::Base.connection.exec_query(sanitized).to_a
      end
    end
  end
end

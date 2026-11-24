# frozen_string_literal: true

module Api
  module V1
    module Helpers
      module AuthHelper
        def raw_request_body
          return "" if request.body.nil?

          request.body.rewind
          body = request.body.read
          request.body.rewind
          body
        end

        def current_merchant
          @current_merchant
        end

        def authenticate_merchant!
          api_key = headers["X-Merchant-Key"] || headers["x-merchant-key"]
          timestamp = headers["X-Timestamp"] || headers["x-timestamp"]
          signature = headers["X-Signature"] || headers["x-signature"]

          merchant = Merchant.active.find_by(api_key: api_key)
          error!({ error: "unauthorized", message: "Invalid merchant credentials" }, 401) unless merchant

          valid = Security::HmacSigner.valid?(
            secret: merchant.api_secret,
            payload: raw_request_body,
            signature: signature,
            timestamp: timestamp,
            check_skew: true
          )

          error!({ error: "unauthorized", message: "Invalid HMAC signature" }, 401) unless valid
          @current_merchant = merchant
        end

        def authenticate_admin!
          expected = ENV.fetch("ADMIN_API_TOKEN", "dev-admin-secret-token")
          auth_header = headers["Authorization"] || headers["authorization"]
          token = auth_header.to_s.sub(/\ABearer\s+/i, "")

          valid = token.bytesize == expected.bytesize && ActiveSupport::SecurityUtils.secure_compare(token, expected)
          error!({ error: "forbidden", message: "Invalid admin token" }, 403) unless valid
        end
      end
    end
  end
end

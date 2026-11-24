# frozen_string_literal: true

module Security
  class HmacSigner
    MAX_CLOCK_SKEW_SECONDS = 300

    def self.sign(secret:, payload:, timestamp: nil)
      body = payload.is_a?(String) ? payload : payload.to_json
      message = timestamp ? "#{timestamp}.#{body}" : body
      OpenSSL::HMAC.hexdigest("SHA256", secret, message)
    end

    def self.valid?(secret:, payload:, signature:, timestamp: nil, check_skew: false)
      return false if secret.blank? || signature.blank?

      if check_skew
        ts = Integer(timestamp, exception: false)
        return false if ts.nil? || (Time.now.to_i - ts).abs > MAX_CLOCK_SKEW_SECONDS
      end

      expected = sign(secret: secret, payload: payload, timestamp: timestamp)
      return false unless expected.bytesize == signature.to_s.bytesize

      ActiveSupport::SecurityUtils.secure_compare(expected, signature.to_s)
    end
  end
end

# frozen_string_literal: true

module Telegram
  class BotService
    def initialize(
      bot_token: ENV.fetch("TELEGRAM_BOT_TOKEN", nil),
      chat_id: ENV.fetch("TELEGRAM_ALERTS_CHAT_ID", nil)
    )
      @bot_token = bot_token
      @chat_id = chat_id
    end

    def notify(text)
      return false if @bot_token.blank? || @chat_id.blank?

      conn = Faraday.new(url: "https://api.telegram.org") do |f|
        f.options.timeout = 3
        f.request :json
      end

      resp = conn.post("/bot#{@bot_token}/sendMessage", {
        chat_id: @chat_id,
        text: text,
        parse_mode: "HTML",
        disable_web_page_preview: true
      })
      resp.success?
    rescue Faraday::Error
      false
    end

    def handle_command(text)
      cmd, arg = text.to_s.strip.split(/\s+/, 2)

      case cmd
      when "/stats"
        rows = Queries::Analytics::MerchantTurnoverQuery.call(since: 24.hours.ago)
        return "No payments in the last 24h." if rows.empty?

        lines = rows.first(5).map do |r|
          "#{r['region']}/#{r['currency']} [#{r['psp_code']}]: #{r['success_count']}/#{r['total_count']} (#{r['conversion_pct']}%) | vol: #{r['gross_captured_minor']}"
        end
        "24h Acquiring Stats:\n#{lines.join("\n")}"
      when "/balance"
        return "Usage: /balance <merchant_code>" if arg.blank?

        merchant = Merchant.find_by(code: arg.strip)
        return "Merchant '#{arg}' not found." unless merchant

        balances = Queries::Ledger::MerchantBalanceQuery.call(merchant_id: merchant.id)
        return "No ledger accounts for #{merchant.code}." if balances.empty?

        lines = balances.map { |b| "#{b['currency']} #{b['account_type']}: #{b['balance_minor']} minor" }
        "Balances for #{merchant.code}:\n#{lines.join("\n")}"
      when "/stuck"
        count = Payment.where(status: "processing").where("created_at < ?", 15.minutes.ago).count
        "Stuck processing payments (>15m): #{count}"
      else
        "Available commands: /stats, /balance <merchant_code>, /stuck"
      end
    end
  end
end

# frozen_string_literal: true

module Api
  module V1
    class WebhooksApi < Grape::API
      helpers Api::V1::Helpers::AuthHelper

      resource :webhooks do
        desc "Receive signed callback from upstream PSP"
        post "psp/:provider" do
          signature = headers["X-Psp-Signature"] || headers["X-PSP-Signature"] || headers["x-psp-signature"]
          result = ::Payments::ProcessPspWebhook.new.call(
            provider_code: params[:provider],
            raw_body: raw_request_body,
            signature: signature,
            params: params.to_h.symbolize_keys.except(:provider)
          )

          if result.success?
            data = result.value!
            status 200
            {
              ok: true,
              idempotent_replay: data[:idempotent_replay],
              status: data[:payment].status
            }
          else
            code, details = result.failure
            http_status = case code
            when :invalid_signature then 401
            when :psp_not_found, :payment_not_found then 404
            else 422
            end
            error!({ error: code, details: details }, http_status)
          end
        end

        desc "Telegram Bot command webhook"
        post :telegram do
          expected = ENV.fetch("TELEGRAM_WEBHOOK_SECRET", "dev-tg-secret")
          secret = headers["X-Telegram-Bot-Api-Secret-Token"] || headers["x-telegram-bot-api-secret-token"]
          unless secret.to_s.bytesize == expected.bytesize && ActiveSupport::SecurityUtils.secure_compare(secret.to_s, expected)
            error!({ error: "unauthorized" }, 401)
          end

          text = params.dig(:message, :text)
          reply = ::Telegram::BotService.new.handle_command(text)
          status 200
          { reply: reply }
        end
      end
    end
  end
end

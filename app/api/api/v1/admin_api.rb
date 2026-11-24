# frozen_string_literal: true

module Api
  module V1
    class AdminApi < Grape::API
      helpers Api::V1::Helpers::AuthHelper

      before { authenticate_admin! }

      resource :admin do
        desc "Platform-wide acquiring turnover and PSP health overview"
        get :overview do
          hours = (params[:hours] || 24).to_i.clamp(1, 720)
          {
            turnover: ::Queries::Analytics::MerchantTurnoverQuery.call(since: hours.hours.ago),
            psps: PspProvider.order(priority: :asc).select(:code, :name, :region, :supported_currencies, :priority, :cost_bps, :health_score, :active),
            pending_webhooks: WebhookDelivery.where(status: %w[pending processing]).count
          }
        end

        desc "Customize merchant routing rules and fee/reserve terms"
        patch "merchants/:code/routing" do
          merchant = Merchant.find_by(code: params[:code])
          error!({ error: "not_found" }, 404) unless merchant

          rules = (merchant.custom_routing_rules || {}).merge(
            "preferred_psp" => params[:preferred_psp],
            "excluded_psps" => Array(params[:excluded_psps])
          ).compact

          attrs = { custom_routing_rules: rules }
          attrs[:fee_bps] = params[:fee_bps].to_i if params[:fee_bps].present?
          attrs[:rolling_reserve_bps] = params[:rolling_reserve_bps].to_i if params[:rolling_reserve_bps].present?

          merchant.update!(attrs)
          { merchant: merchant.slice(:code, :name, :fee_bps, :rolling_reserve_bps, :custom_routing_rules) }
        end

        desc "Dispatch due outbox webhooks using PostgreSQL SKIP LOCKED"
        post "outbox/dispatch" do
          summary = ::Outbox::DispatchWebhooks.new.call(batch_size: (params[:batch_size] || 25).to_i.clamp(1, 100))
          { dispatched: summary }
        end
      end
    end
  end
end

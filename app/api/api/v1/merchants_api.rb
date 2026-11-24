# frozen_string_literal: true

module Api
  module V1
    class MerchantsApi < Grape::API
      helpers Api::V1::Helpers::AuthHelper

      before { authenticate_merchant! }

      resource :merchants do
        desc "Get merchant ledger balances verified against double-entry journal"
        get :balance do
          balances = ::Queries::Ledger::MerchantBalanceQuery.call(merchant_id: current_merchant.id)
          {
            merchant_code: current_merchant.code,
            balances: balances
          }
        end

        desc "Get merchant conversion & turnover analytics"
        get :analytics do
          hours = (params[:hours] || 24).to_i.clamp(1, 720)
          rows = ::Queries::Analytics::MerchantTurnoverQuery.call(
            since: hours.hours.ago,
            merchant_id: current_merchant.id
          )
          {
            merchant_code: current_merchant.code,
            window_hours: hours,
            breakdown: rows
          }
        end
      end
    end
  end
end

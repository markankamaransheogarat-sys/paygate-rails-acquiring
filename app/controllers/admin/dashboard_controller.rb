# frozen_string_literal: true

module Admin
  class DashboardController < ApplicationController
    def index
      @turnover = Queries::Analytics::MerchantTurnoverQuery.call(since: 30.days.ago)
      @psps = PspProvider.order(priority: :asc)
      @merchants = Merchant.order(created_at: :desc)
      @recent_payments = Payment.includes(:merchant, :psp_provider).order(created_at: :desc).limit(15)
      @outbox_stats = WebhookDelivery.group(:status).count
    end
  end
end

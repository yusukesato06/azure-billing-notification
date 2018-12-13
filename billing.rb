require 'rest-client'
require "slack-notifier"
require 'json'
require 'erb'
include ERB::Util

require File.dirname(__FILE__) + '/lib/initialize.rb'
require File.dirname(__FILE__) + '/lib/call_azure_api.rb'
require File.dirname(__FILE__) + '/lib/caluculate_cost.rb'
require File.dirname(__FILE__) + '/lib/notify.rb'

if __FILE__ == $0
  LOG_OUT.info "Billing function is called."

  ### APIコール用オブジェクトの初期化
  call_azure_api = CallAzureApi.new(APPLICATION_ID, CLIENT_ASSERTION_TYPE, CLIENT_ASSERTION, TENANT_ID, SUBSCRIPTION_ID, OFFER_DURABLE_ID)
  ### Slack通知用オブジェクトの初期化
  slack_notification = Notify.new(SLACK_WEBHOOK_URL, SLACK_CHANNEL, SLACK_USERNAME)

  ### Token取得
  call_azure_api.get_token
  ### Rate取得
  rate = call_azure_api.get_rate_meter

  ### Dailyの合計金額計算
  usages_daily = call_azure_api.get_usage(START_TIME_D, END_TIME)
  calc_cost_daily = CaluculateCost.new(usages_daily, rate)
  calc_cost_daily.correlate_usage_to_rate
  total_cost_daily = calc_cost_daily.calc_total_cost
  rg_total_cost_dayly = calc_cost_daily.calc_rg_total_cost
  
  ### Dailyの合計金額通知
  slack_notification.notify_cost_data(total_cost_daily, rg_total_cost_dayly, "Azure Cost(Daily)", START_TIME_D, END_TIME)

  ### Monthlyの合計金額計算
  usages_monthly = call_azure_api.get_usage(START_TIME_M, END_TIME)
  calc_cost_monthly = CaluculateCost.new(usages_monthly, rate)
  calc_cost_monthly.correlate_usage_to_rate
  total_cost_monthly = calc_cost_monthly.calc_total_cost
  rg_total_cost_monthly = calc_cost_monthly.calc_rg_total_cost

  ### Monthlyの合計金額通知
  slack_notification.notify_cost_data(total_cost_monthly, rg_total_cost_monthly, "Azure Cost(Monthly)", START_TIME_M, END_TIME)

  LOG_OUT.info "All processing is end."
end
require 'inifile'
require 'rest-client'
require 'json'
require "slack-notifier"
require 'erb'
include ERB::Util

INIFILE           = IniFile.load('./auth.ini') 
APPLICATION_ID    = INIFILE['Azure']['APPLICATION_ID']
CLIENT_SECRET     = INIFILE['Azure']['CLIENT_SECRET']
TENANT_ID         = INIFILE['Azure']['TENANT_ID']
SUBSCRIPTION_ID   = INIFILE['Azure']['SUBSCRIPTION_ID']
OFFER_DURABLE_ID  = INIFILE['Azure']['OFFER_DURABLE_ID'] # 契約固有の値
SLACK_WEBHOOK_URL = INIFILE['Slack']['WEBHOOK_URL']

NOW = DateTime.now.new_offset(0)
START_TIME_M =  DateTime.new(NOW.year, NOW.month, 1, 0, 0, 0)
START_TIME_D =  DateTime.new(NOW.year, NOW.month, NOW.day-1, 0, 0, 0)
END_TIME =  DateTime.new(NOW.year, NOW.month, NOW.day, 0, 0, 0)

class Usage
  attr_accessor :meter_name
  attr_accessor :meter_category
  attr_accessor :meter_sub_category
  attr_accessor :meter_id
  attr_accessor :meter_region
  attr_accessor :quantity
  attr_accessor :name
  attr_accessor :rate
  attr_accessor :included_quantity
  attr_accessor :instande_name
  attr_accessor :resource_group_name
end

# トークンを取得
def api_token(application_id, client_secret, tenant_id)
  url = "https://login.microsoftonline.com/#{tenant_id}/oauth2/token?api-version=1.0"
  payload = {
    'grant_type' => 'client_credentials',
    'client_id' => application_id,
    'client_secret' => client_secret,
    'resource' => "https://management.azure.com/"
  }
  headers = {
    "Content-Type" => "application/x-www-form-urlencoded"
  }
  RestClient.post(url, payload, headers){ |response, request, result, &block|
    case response.code
    when 200
      json = JSON.parse(response)
      token = json["access_token"]
      token
    else
      false
    end
  }
end

# リソース利用量を取得
def usages(token, subscription_id, start_time)
  url = "https://management.azure.com/subscriptions/#{subscription_id}/providers/Microsoft.Commerce/UsageAggregates?api-version=2015-06-01-preview&reportedStartTime=#{url_encode(start_time.to_s)}&reportedEndTime=#{url_encode(END_TIME.to_s)}&aggreagationGranularity=Monthly&showDetails=false"
  headers = {
    "Content-type" => "application/json",
    "Authorization" => "Bearer #{token}"
  }

  results = []
  next_link = ""

  while true do
    # next_linkがなければループを抜ける
    if next_link == nil
      break
    # next_linkがあれば、再度リクエスト
    elsif next_link != ""
      url = next_link
    end
    RestClient.get(url, headers){ |response, request, result, &block|
      case response.code
      when 200
        json = JSON.parse(response)
        # nextLinkの確認
        next_link = json['nextLink']
        json['value'].each do |item|
          # instanceDataを:で分割
          # 後方データを整形して配列に格納
          instance_data = item['properties']['instanceData'].split(":")[2].split(",")[0].delete("\"").split("/")
          u = Usage.new
          u.meter_id = item['properties']['meterId']
          u.quantity = item['properties']['quantity']
          u.name = item['name']
          # 配列のリソースグループ名を格納
          u.resource_group_name = instance_data[4]
          # 配列のインスタンスデータを格納
          u.instance_name = instance_data[8]
          results.push(u)
        end
      else
        STDERR.puts "Error: 利用量取得に失敗しました"
        STDERR.puts "Code：#{response.code}"
        STDERR.puts "Header: #{response.headers}"
        STDERR.puts "Body: #{response.body}"
        exit 1
      end
    }
  end
  results
end

# サービス単価を取得
def rate_meters(token, subscription_id, offer_durable_id)
  url = "https://management.azure.com/subscriptions/#{subscription_id}/providers/Microsoft.Commerce/RateCard?api-version=2015-06-01-preview&$filter=OfferDurableId eq '#{offer_durable_id}' and Currency eq 'JPY' and Locale eq 'ja-JP' and RegionInfo eq 'JP'"
  headers = {
    "Content-type" => "application/json",
    "Authorization" => "Bearer #{token}"
  }
  redirect_url = ""

  RestClient.get(url, headers){ |response, request, result, &block|
    redirect_url = response.headers[:location]
  }

  RestClient.get(redirect_url){ |response, request, result, &block|
    case response.code
    when 200
      json = JSON.parse(response)
      json['Meters']
    else
      STDERR.puts "Error: レート取得に失敗しました"
      STDERR.puts "Code：#{response.code}"
      STDERR.puts "Header: #{response.headers}"
      STDERR.puts "Body: #{response.body}"
      exit 1
    end
  }
end

# リソース利用量とサービス単価を紐付け
def usages_with_rate(usages, meters)
  usages.each do |u|
    meters.each do |j|
      # usagesとrateをMeterIDで紐付け
      next unless j['MeterId'] == u.meter_id
      u.meter_name = j['MeterName']
      u.meter_category = j['MeterCategory']
      u.meter_sub_category = j['MeterSubCategory']
      u.meter_region = j['MeterRegion']
      u.rate = j['MeterRates']['0']
      u.included_quantity = j['IncludedQuantity']
    end
  end
  usages
end

# 全体コストを計算
def calc_cost(usages)
  total_cost = 0
  usages.each do |u|
    unless u.rate == nil
      total_cost += u.quantity * u.rate
    end
  end
  total_cost
end

# リソースグループ毎のコストを計算
def calc_cost_rg(usages)
  total_cost_rg = {}
  usages.each do |u|
    unless u.rate == nil
      cost = u.quantity * u.rate
      if !total_cost_rg[u.resource_group_name]
        total_cost_rg[u.resource_group_name] = cost
      else
        total_cost_rg[u.resource_group_name] += cost
      end
    end
  end
  total_cost_rg = Hash[ total_cost_rg.sort_by{ |_, v| -v } ]
  total_cost_rg
end
  
# Slackへの料金通知
def slack_notification(total_cost, total_cost_rg, pretext, start_time)
  notifier = Slack::Notifier.new( SLACK_WEBHOOK_URL, channel: "#azure_billing", username: 'Azure Billing Notifier')
  attachments = {pretext: pretext, color: "good",fields: [
                    "title": "期間",
                    "value": "#{start_time.strftime("%Y/%m/%d")} 〜 #{END_TIME.strftime("%Y/%m/%d")}",
                    "short": false
                  ]
                }
  item = { "title": "合計コスト", "value": "#{total_cost.round}円"}
  attachments[:fields].push(item)
  attachments[:fields].push({"title": "リソースグループ別コスト"})
  total_cost_rg.each do |key, value|
    item = { "title": key, "value": "#{value.round}円" , "short": true }
    attachments[:fields].push(item)
  end
  notifier.post attachments: [attachments]
end

if __FILE__ == $0
  puts "* 処理を開始します"
  
  puts "* トークンを取得します"
  token = api_token(APPLICATION_ID, CLIENT_ASSERTION_TYPE, CLIENT_ASSERTION, TENANT_ID)
  puts "* トークンを取得しました"

  puts "* レートを取得します"
  rate = rate_meters(token, SUBSCRIPTION_ID, OFFER_DURABLE_ID)
  puts "* レートを取得しました"

  puts "* Dailyの合計金額を取得します"
  usages_d = usages(token, SUBSCRIPTION_ID, START_TIME_D)
  puts "* Dailyの合計金額を取得しました"
  usages_d = usages_with_rate(usages_d, rate)
  total_cost_d = calc_cost(usages_d)
  total_cost_rg_d = calc_cost_rg(usages_d)
  puts "* Dailyの合計金額を通知します"
  slack_notification(total_cost_d, total_cost_rg_d, "Azure利用料金(Daily)", START_TIME_D)
  puts "* Dailyの合計金額を通知しました"

  puts "* Monthlyの合計金額を取得します"
  usages_m = usages(token, SUBSCRIPTION_ID, START_TIME_M)
  puts "* Monthlyの合計金額を取得しました"
  usages_m = usages_with_rate(usages_m, rate)
  total_cost_m = calc_cost(usages_m)
  total_cost_rg_m = calc_cost_rg(usages_m)
  puts "* Monthlyの合計金額を通知します"
  slack_notification(total_cost_m, total_cost_rg_m, "Azure利用料金(Monthly)", START_TIME_M)
  puts "* Monthlyの合計金額を通知しました"

  puts "* 処理をを終了します"
end

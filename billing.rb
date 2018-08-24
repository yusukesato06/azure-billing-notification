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

def usages(token, subscription_id)
  granularity = "Monthly"

  url = "https://management.azure.com/subscriptions/#{subscription_id}/providers/Microsoft.Commerce/UsageAggregates?api-version=2015-06-01-preview&reportedStartTime=#{url_encode(START_TIME_M.to_s)}&reportedEndTime=#{url_encode(END_TIME.to_s)}&aggreagationGranularity=#{granularity}&showDetails=false"
  headers = {
    "Content-type" => "application/json",
    "Authorization" => "Bearer #{token}"
  }

  results = []
  RestClient.get(url, headers){ |response, request, result, &block|
    case response.code
    when 200
      json = JSON.parse(response)
      json['value'].each do |item|
        instande_data = item['properties']['instanceData'].split(":")[2].split(",")[0].delete("\"").split("/")
        u = Usage.new
        u.meter_id = item['properties']['meterId']
        u.quantity = item['properties']['quantity']
        u.name = item['name']
        u.resource_group_name = instande_data[4]
        u.instande_name = instande_data[8]
        results.push(u)
      end
      results
    else
      false
    end
  }
end

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
      response.headers
    end
  }
end

def usages_with_rate(usages, meters)
  usages.each do |u|
    meters.each do |j|
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

def calc_cost(usages)
  total_cost = 0
  usages.each do |u|
    unless u.rate == nil
      total_cost += u.quantity * u.rate
    end
  end
  total_cost
end

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
  
def slack_notification(total_cost, total_cost_rg)
  notifier = Slack::Notifier.new( SLACK_WEBHOOK_URL, username: 'Azure Billing Notifier')
  attachments = {pretext: 'Azure利用料金', color: "good",fields: [
                    "title": "期間",
                    "value": "#{START_TIME_M.strftime("%Y/%m/%d")} 〜 #{END_TIME.strftime("%Y/%m/%d")}",
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

token = api_token(APPLICATION_ID, CLIENT_SECRET, TENANT_ID)
usages = usages(token, SUBSCRIPTION_ID)
rate = rate_meters(token, SUBSCRIPTION_ID, OFFER_DURABLE_ID)
usages = usages_with_rate(usages, rate)
total_cost = calc_cost(usages)
total_cost_rg = calc_cost_rg(usages)
slack_notification(total_cost, total_cost_rg)

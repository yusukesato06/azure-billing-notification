require 'logger'

require File.dirname(__FILE__) + '/usage.rb'

class CallAzureApi
  def initialize(application_id, client_assertion_type, client_assertion, tenant_id, subscription_id, offer_durable_id)
    @application_id         = application_id
    @client_assertion_type  = client_assertion_type
    @client_assertion       = client_assertion
    @tenant_id              = tenant_id
    @subscription_id        = subscription_id
    @offer_durable_id       = offer_durable_id
    @token                  = ""
  end

  ### Azure APIトークンの取得
  def get_token
    LOG_OUT.info "Getting token."

    url = "https://login.microsoftonline.com/#{@tenant_id}/oauth2/token?api-version=1.0"
    payload = {
      'grant_type' => 'client_credentials',
      'client_id' => @application_id,
      'client_assertion_type' => @client_assertion_type,
      'client_assertion' => @client_assertion,
      'resource' => "https://management.azure.com/"
    }
    headers = {
      "Content-Type" => "application/x-www-form-urlencoded"
    }

    RestClient.post(url, payload, headers){ |response, request, result, &block|
      case response.code
      when 200
        json = JSON.parse(response)
        @token = json["access_token"]
        LOG_OUT.info "Done."
      else
        LOG_ERR.error "Getting token fails."
        LOG_ERR.error "Code：#{response.code}"
        LOG_ERR.error "Header: #{response.headers}"
        LOG_ERR.error "Body: #{response.body}"
        exit 1
      end
    } 
  end

  ### サービス毎のレートを取得
  def get_rate_meter
    LOG_OUT.info "Getting rate."

    url = "https://management.azure.com/subscriptions/#{@subscription_id}/providers/Microsoft.Commerce/RateCard?api-version=2015-06-01-preview&$filter=OfferDurableId eq '#{@offer_durable_id}' and Currency eq 'JPY' and Locale eq 'ja-JP' and RegionInfo eq 'JP'"
    headers = {
      "Content-type" => "application/json",
      "Authorization" => "Bearer #{@token}"
    }
    redirect_url = ""
    request_count = 0
    break_status = false

    ### Azure APIが正常応答するまで繰り返しリクエストを実施
    ### 異常応答する場合、60秒スリープ後に再度リクエスト(最大3回)
    while true do
      RestClient.get(url, headers){ |response, request, result, &block|
        if response.code == 302
          redirect_url = response.headers[:location]
          break_status = true
        elsif response.code == 500
          if request_count >= 3
            LOG_ERR.error "Request count is over 3."
            exit 1
          end
          LOG_ERR.error "Azure API internal server error."
          LOG_ERR.error "Retrying request."
          sleep(60)
          request_count += 1
        end
      }
      if break_status
        break
      end
    end

    if redirect_url != ""
      RestClient.get(redirect_url){ |response, request, result, &block|
        case response.code
        when 200
          json = JSON.parse(response)
          LOG_OUT.info "Done."
          return json['Meters']
        else
          LOG_ERR.error "Getting rate fails."
          LOG_ERR.error "Code：#{response.code}"
          LOG_ERR.error "Header: #{response.headers}"
          LOG_ERR.error "Body: #{response.body}"
          exit 1
        end
      }
    end
  end

  ### 利用量を取得
  def get_usage(start_time, end_time)
    LOG_OUT.info "Getting usage."
    granularity = "Monthly"
    results = []
    next_link = ""

    url = "https://management.azure.com/subscriptions/#{@subscription_id}/providers/Microsoft.Commerce/UsageAggregates?api-version=2015-06-01-preview&reportedStartTime=#{url_encode(start_time.to_s)}&reportedEndTime=#{url_encode(end_time.to_s)}&aggreagationGranularity=#{granularity}&showDetails=false"
    headers = {
      "Content-type" => "application/json",
      "Authorization" => "Bearer #{@token}"
    }

    while true do
      ### next_linkがなければループを抜ける
      if next_link == nil
        break
      ### next_linkがあれば、再度リクエスト
      elsif next_link != ""
        url = next_link
      end

      RestClient.get(url, headers){ |response, request, result, &block|
        case response.code
        when 200
          json = JSON.parse(response)
          ### nextLinkの確認
          next_link = json['nextLink']
          json['value'].each do |item|
            ### instanceDataを:で分割
            ### 後方データを整形して配列に格納
            if item['properties']['instanceData'] != nil
              instance_data = item['properties']['instanceData'].split(":")[2].split(",")[0].delete("\"").split("/")
            else
              instance_data = ""
            end
            usage = Usage.new
            usage.meter_id = item['properties']['meterId']
            usage.quantity = item['properties']['quantity']
            usage.name = item['name']
            ### 配列のリソースグループ名を格納
            usage.resource_group_name = instance_data[4]
            ### 配列のインスタンスデータを格納
            usage.instance_name = instance_data[8]
            results.push(usage)
          end
        else
          LOG_ERR.error "Getting usage fails."
          LOG_ERR.error "Code：#{response.code}"
          LOG_ERR.error "Header: #{response.headers}"
          LOG_ERR.error "Body: #{response.body}"
          exit 1
        end
      }
    end
    LOG_OUT.info "Done."
    return results
  end
end
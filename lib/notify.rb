require 'logger'

class Notify
  def initialize(slack_webhook_url, slack_channel, slack_username)
    @notifier = Slack::Notifier.new( slack_webhook_url, channel: slack_channel, username: slack_username)
  end

  def notify_cost_data(total_cost, total_cost_rg, pretext, start_time, end_time)
    LOG_OUT.info "Notification #{pretext} to slack."

    attachments = {pretext: pretext, color: "good",fields: [
                      "title": "期間",
                      "value": "#{start_time.strftime("%Y/%m/%d")} 〜 #{end_time.strftime("%Y/%m/%d")}",
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
    @notifier.post attachments: [attachments]
    LOG_OUT.info "Done."
  end
end
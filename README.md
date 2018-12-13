azure-billing-notification
====

This script notify azure cost by slack.

## Preparation

You need to prepare at least those variables as follows.
It assumes that app authentication is based on client certificate.

- AppId
- SubscriptionId
- TenantId
- client assertion (JWT)
- Slack Webhook URL
- Slack channel
- Slack username

## Install

```
git clone https://github.com/yusukesato06/azure-billing-notification.git
cd azure-billing-notification
bundle install
```
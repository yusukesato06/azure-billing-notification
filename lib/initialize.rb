require 'inifile'
require 'logger'

# Initファイルの読み込み
INIFILE_PATH  = File.dirname(__FILE__).chomp('lib') + 'auth.ini'
INIFILE       = IniFile.load( INIFILE_PATH )

# Initファイルから情報呼び出し
### Azure
APPLICATION_ID        = INIFILE['Azure']['APPLICATION_ID']
CLIENT_ASSERTION_TYPE = INIFILE['Azure']['CLIENT_ASSERTION_TYPE']
CLIENT_ASSERTION      = INIFILE['Azure']['CLIENT_ASSERTION']
TENANT_ID             = INIFILE['Azure']['TENANT_ID']
SUBSCRIPTION_ID       = INIFILE['Azure']['SUBSCRIPTION_ID']
OFFER_DURABLE_ID      = INIFILE['Azure']['OFFER_DURABLE_ID'] # 契約固有の値
### Slack
SLACK_WEBHOOK_URL     = INIFILE['Slack']['WEBHOOK_URL']
SLACK_CHANNEL         = INIFILE['Slack']['CHANNEL']
SLACK_USERNAME        = INIFILE['Slack']['SLACK_USERNAME']

# 取得日時の初期化
TODAY         = DateTime.now.new_offset(0)
YESTERDAY     = DateTime.now.new_offset(0) - 1
START_TIME_D  = DateTime.new(YESTERDAY.year, YESTERDAY.month, YESTERDAY.day, 0, 0, 0) # 1日分取得用の開始日
START_TIME_M  = DateTime.new(TODAY.year, TODAY.month, 1, 0, 0, 0) # 今月分取得用の開始日
END_TIME      = DateTime.new(TODAY.year, TODAY.month, TODAY.day, 0, 0, 0)

# ログオブジェクトの初期化
LOG_OUT = Logger.new(STDOUT)
LOG_ERR = Logger.new(STDERR)
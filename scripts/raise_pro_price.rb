#!/usr/bin/env ruby
# Sets the Honest Signal Pro one-time purchase to a new UK price on BOTH
# stores, and refreshes the Play product description to the current feature
# list. Run it when the release that justifies the price is live, not before.
#
#   ruby scripts/raise_pro_price.rb            # dry run: prints what would change
#   ruby scripts/raise_pro_price.rb --apply    # makes the change
#
# Requires PLAY_JSON_KEY, ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH and the
# googleauth + jwt gems (same as the other release scripts).
#
# Google Play: the product is a migrated "one-time product" (the legacy
#   inappproducts API answers 403 for it). Every region gets Google's own
#   conversion of the GBP price via pricing:convertRegionPrices, the same
#   numbers "Set price → apply exchange rates" gives in the console, so no
#   region keeps the old price by accident. Region availability is preserved.
# App Store: GBR is the base territory with one manual price; replacing it
#   lets Apple re-equalise every other territory from the new base price.
#   The new price applies immediately (startDate null).
#
# Existing buyers are unaffected on both stores: a non-consumable that has been
# bought stays owned whatever the current price is.
require 'json'
require 'net/http'
require 'uri'
require 'googleauth'
require 'jwt'
require 'openssl'

APPLY = ARGV.include?('--apply')
NEW_GBP = '4.99'
PACKAGE = 'com.froggyeye.honestsignal'
SKU = 'com.froggyeye.honestsignal.pro'
APP_ID = '6799269422'
PLAY_DESCRIPTION =
  '30 days of history with every drop-out listed, PDF and CSV reports for ' \
  'your provider, drop-out alerts, the floating indicator, custom intervals ' \
  'and indicator themes. One payment, no subscription.'

def http(method, url, auth, body = nil)
  uri = URI(url)
  klass = { get: Net::HTTP::Get, post: Net::HTTP::Post, patch: Net::HTTP::Patch }.fetch(method)
  request = klass.new(uri)
  request['Authorization'] = auth
  request['Content-Type'] = 'application/json'
  request.body = JSON.generate(body) if body
  response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, read_timeout: 120) { |h| h.request(request) }
  parsed = response.body.to_s.empty? ? {} : (JSON.parse(response.body) rescue { 'raw' => response.body })
  abort "#{method.upcase} #{url}: HTTP #{response.code}: #{parsed}" unless response.code.to_i.between?(200, 299)
  parsed
end

def money(price)
  units = price['units'].to_i
  nanos = price['nanos'].to_i
  format('%<cur>s %<amount>.2f', cur: price['currencyCode'], amount: units + nanos / 1e9)
end

puts APPLY ? '=== APPLYING ===' : '=== DRY RUN (pass --apply to change prices) ==='

# ---------------------------------------------------------------- Google Play
play = Google::Auth::ServiceAccountCredentials.make_creds(
  json_key_io: File.open(ENV.fetch('PLAY_JSON_KEY')),
  scope: 'https://www.googleapis.com/auth/androidpublisher'
)
play.fetch_access_token!
play_auth = "Bearer #{play.access_token}"
base = "https://androidpublisher.googleapis.com/androidpublisher/v3/applications/#{PACKAGE}"

product = http(:get, "#{base}/oneTimeProducts/#{SKU}", play_auth)
option = product.fetch('purchaseOptions').find { |o| o['purchaseOptionId'] == 'pro' } ||
         abort('Play: purchase option "pro" not found')
regions = option.fetch('regionalPricingAndAvailabilityConfigs')
gb = regions.find { |r| r['regionCode'] == 'GB' } || abort('Play: no GB price')
puts "Play: GB now #{money(gb['price'])}, #{regions.size} regions"

# convertRegionPrices takes a tax-EXCLUSIVE price and adds local tax where
# prices are shown tax-inclusive (it turns GBP 4.99 into GBP 5.99 for the UK).
# The live prices were set from the VAT-inclusive UK figure, so convert from
# the ex-VAT equivalent and then pin the UK price to the exact advertised one.
UK_VAT = 1.2
# The exact quotient, not rounded to pence (house-facts #18, docs/ASO.md §6).
ex_vat = NEW_GBP.to_f / UK_VAT
units = ex_vat.floor
nanos = ((ex_vat - units) * 1e9).round
converted = http(:post, "#{base}/pricing:convertRegionPrices", play_auth, {
  price: { currencyCode: 'GBP', units: units.to_s, nanos: nanos }
})
by_region = converted.fetch('convertedRegionPrices')
new_units, new_pence = NEW_GBP.split('.')
exact_gb = { 'currencyCode' => 'GBP', 'units' => new_units, 'nanos' => new_pence.ljust(9, '0').to_i }
updated = regions.map do |region|
  next region unless region['price']
  next region.merge('price' => exact_gb) if region['regionCode'] == 'GB'

  conversion = by_region[region['regionCode']]
  abort("Play: no converted price for #{region['regionCode']}") unless conversion
  region.merge('price' => conversion.fetch('price'))
end
converted_gb = by_region.dig('GB', 'price')
puts "Play: converted from GBP #{format('%.4f', ex_vat)} ex-VAT " \
     "(Google's own GB figure #{converted_gb ? money(converted_gb) : 'n/a'}, pinned to GBP #{NEW_GBP})"
%w[US DE IE AU CA].each do |code|
  before = regions.find { |r| r['regionCode'] == code }
  after = updated.find { |r| r['regionCode'] == code }
  puts "  #{code}: #{money(before['price'])} -> #{money(after['price'])}" if before && after
end

if APPLY
  product['purchaseOptions'] = product['purchaseOptions'].map do |o|
    o['purchaseOptionId'] == 'pro' ? o.merge('regionalPricingAndAvailabilityConfigs' => updated) : o
  end
  product['listings'] = product.fetch('listings').map do |l|
    l['languageCode'] == 'en-GB' ? l.merge('description' => PLAY_DESCRIPTION) : l
  end
  http(:patch,
       "#{base}/oneTimeProducts/#{SKU}?updateMask=purchaseOptions,listings" \
       '&regionsVersion.version=2022/02',
       play_auth, product)
  check = http(:get, "#{base}/oneTimeProducts/#{SKU}", play_auth)
  gb_now = check['purchaseOptions'].find { |o| o['purchaseOptionId'] == 'pro' }
                ['regionalPricingAndAvailabilityConfigs'].find { |r| r['regionCode'] == 'GB' }
  puts "Play: read back GB #{money(gb_now['price'])}"
else
  puts "Play: would set GB to GBP #{NEW_GBP} and convert #{updated.count { |r| r['price'] }} regions"
end

# ------------------------------------------------------------------ App Store
token = JWT.encode(
  { iss: ENV.fetch('ASC_ISSUER_ID'), aud: 'appstoreconnect-v1', exp: Time.now.to_i + 1200 },
  OpenSSL::PKey::EC.new(File.read(ENV.fetch('ASC_KEY_PATH'))),
  'ES256', { kid: ENV.fetch('ASC_KEY_ID'), typ: 'JWT' }
)
asc_auth = "Bearer #{token}"
asc = 'https://api.appstoreconnect.apple.com'

iaps = http(:get, "#{asc}/v1/apps/#{APP_ID}/inAppPurchasesV2?limit=50", asc_auth)
iap = iaps['data'].find { |d| d.dig('attributes', 'productId') == SKU } || abort('ASC: IAP not found')
iap_id = iap['id']

schedule = http(:get, "#{asc}/v2/inAppPurchases/#{iap_id}/iapPriceSchedule" \
                      '?include=baseTerritory,manualPrices', asc_auth)
base_territory = schedule.dig('data', 'relationships', 'baseTerritory', 'data', 'id')
abort("ASC: base territory is #{base_territory}, expected GBR") unless base_territory == 'GBR'

points = []
url = "#{asc}/v2/inAppPurchases/#{iap_id}/pricePoints?filter[territory]=GBR&limit=200"
while url
  page = http(:get, url, asc_auth)
  points.concat(page['data'])
  url = page.dig('links', 'next')
end
point = points.find { |p| p.dig('attributes', 'customerPrice') == NEW_GBP } ||
        abort("ASC: no GBR price point at #{NEW_GBP}")
puts "ASC: GBR price point #{NEW_GBP} = #{point['id']} (proceeds #{point.dig('attributes', 'proceeds')})"

if APPLY
  http(:post, "#{asc}/v1/inAppPurchasePriceSchedules", asc_auth, {
    data: {
      type: 'inAppPurchasePriceSchedules',
      relationships: {
        inAppPurchase: { data: { type: 'inAppPurchases', id: iap_id } },
        baseTerritory: { data: { type: 'territories', id: 'GBR' } },
        manualPrices: { data: [{ type: 'inAppPurchasePrices', id: '${new-gbr}' }] }
      }
    },
    included: [{
      type: 'inAppPurchasePrices',
      id: '${new-gbr}',
      attributes: { startDate: nil },
      relationships: {
        inAppPurchasePricePoint: { data: { type: 'inAppPurchasePricePoints', id: point['id'] } }
      }
    }]
  })
  puts 'ASC: price schedule replaced; other territories re-equalise from GBR.'
else
  puts "ASC: would replace the schedule with GBR #{NEW_GBP}, starting now"
end

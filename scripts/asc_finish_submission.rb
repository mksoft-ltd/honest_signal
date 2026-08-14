# Finishes the App Store submission once the two console-only steps are done.
#
#   1. Founder publishes the App Privacy nutrition label (Data Not Collected).
#   2. Someone clicks "Add for Review" on the IAP's own page and picks the
#      existing Draft submission. There is no API for this: POST
#      /reviewSubmissionItems rejects both `inAppPurchase` and `inAppPurchaseV2`
#      with ENTITY_ERROR.RELATIONSHIP.UNKNOWN — appStoreVersion is the only
#      reviewable relationship it accepts.
#
# Then run this. It adds the version to the same submission, refuses to submit
# unless the submission holds BOTH items, and submits.
#
#   GEM_HOME=/opt/homebrew/Cellar/fastlane/<ver>/libexec GEM_PATH=$GEM_HOME \
#     /opt/homebrew/opt/ruby/bin/ruby scripts/asc_finish_submission.rb
#
# Reads ASC_KEY_ID / ASC_ISSUER_ID / ASC_KEY_PATH from the environment.
require 'jwt'
require 'net/http'
require 'json'
require 'uri'

APP = '6799269422'
VID = 'fbca4bfc-4358-44fb-9f0f-6303218919e3'

TOKEN = JWT.encode(
  { iss: ENV.fetch('ASC_ISSUER_ID'), aud: 'appstoreconnect-v1', exp: Time.now.to_i + 1200 },
  OpenSSL::PKey::EC.new(File.read(ENV.fetch('ASC_KEY_PATH'))),
  'ES256', { kid: ENV.fetch('ASC_KEY_ID'), typ: 'JWT' }
)

def asc(method, path, body = nil)
  uri = URI("https://api.appstoreconnect.apple.com/v1#{path}")
  http = Net::HTTP.new(uri.host, 443)
  http.use_ssl = true
  req = { get: Net::HTTP::Get, post: Net::HTTP::Post,
          patch: Net::HTTP::Patch }.fetch(method).new(uri.request_uri)
  req['Authorization'] = "Bearer #{TOKEN}"
  req['Content-Type'] = 'application/json'
  req.body = JSON.generate(body) if body
  res = http.request(req)
  [res.code.to_i, (JSON.parse(res.body) rescue nil)]
end

code, b = asc(:get, "/apps/#{APP}/reviewSubmissions?filter[state]=READY_FOR_REVIEW&include=items")
sub = (b['data'] || []).first
abort('No open submission found. Create one in the console or via POST /reviewSubmissions.') unless sub
sid = sub['id']
items = sub.dig('relationships', 'items', 'data') || []
puts "submission #{sid}: #{items.size} item(s) before adding the version"

# The version may already be in the submission — decide from its own state,
# because re-adding one fails with a misleading NOT_ALLOWED error.
code, v = asc(:get, "/appStoreVersions/#{VID}?fields[appStoreVersions]=appStoreState")
state = v.dig('data', 'attributes', 'appStoreState')
puts "version state: #{state}"

if state == 'READY_FOR_REVIEW'
  puts 'version already attached to a submission — skipping the add'
else
  code, r = asc(:post, '/reviewSubmissionItems', {
    data: { type: 'reviewSubmissionItems',
            relationships: {
              reviewSubmission: { data: { type: 'reviewSubmissions', id: sid } },
              appStoreVersion:  { data: { type: 'appStoreVersions', id: VID } } } }
  })
  if code != 201
    (r['errors'] || []).each { |e| warn "  [#{e['code']}] #{e['detail']}" }
    abort('Could not add the version. If this says the resource cannot be reviewed, ' \
          'the App Privacy nutrition label has not been published yet.')
  end
  puts 'version added'
end

code, b = asc(:get, "/reviewSubmissions/#{sid}?include=items")
count = (b['included'] || []).size
puts "submission now holds #{count} item(s)"
if count < 2
  abort("REFUSING TO SUBMIT: expected 2 items (app version + IAP), found #{count}. " \
        "Add the IAP from its own page with \"Add for Review\" and pick this " \
        "submission, then re-run. Submitting without it strands the IAP behind a " \
        'full review cycle, with no way back once queued.')
end

code, b = asc(:patch, "/reviewSubmissions/#{sid}",
              { data: { type: 'reviewSubmissions', id: sid, attributes: { submitted: true } } })
puts "submit -> #{code}"
(b['errors'] || []).each { |e| puts "  [#{e['code']}] #{e['detail']}" } if b && b['errors']

code, b = asc(:get, "/appStoreVersions/#{VID}?fields[appStoreVersions]=appStoreState")
puts "final version state: #{b.dig('data', 'attributes', 'appStoreState')} (WAITING_FOR_REVIEW = success)"

# Register the iOS widget extension's bundle ID and App Store provisioning
# profile, then install the profile locally. Idempotent: re-running reuses the
# bundle ID, and reuses the profile while it is ACTIVE and signed by the same
# certificate as the app's profile (otherwise it is recreated).
#
# Manual signing because the ASC API key has the App Manager role, which Xcode
# cloud signing refuses (see ios/ExportOptions.plist).
#
# Usage: ruby scripts/asc_register_widget.rb
require 'jwt'
require 'net/http'
require 'json'
require 'openssl'
require 'uri'
require 'base64'
require 'fileutils'
require 'tempfile'

WIDGET_BUNDLE_ID = 'com.froggyeye.honestsignal.widget'
WIDGET_BUNDLE_NAME = 'Honest Signal Widget'
WIDGET_PROFILE_NAME = 'HonestSignal Widget App Store'
APP_PROFILE_NAME = 'HonestSignal App Store'
PROFILES_DIR = File.expand_path('~/Library/MobileDevice/Provisioning Profiles')

token = JWT.encode(
  {iss: ENV.fetch('ASC_ISSUER_ID'), aud: 'appstoreconnect-v1', exp: Time.now.to_i + 1200},
  OpenSSL::PKey::EC.new(File.read(ENV.fetch('ASC_KEY_PATH'))),
  'ES256', {kid: ENV.fetch('ASC_KEY_ID'), typ: 'JWT'}
)

def asc(method, path, token, body = nil)
  uri = URI("https://api.appstoreconnect.apple.com/v1#{path}")
  req = {get: Net::HTTP::Get, post: Net::HTTP::Post, delete: Net::HTTP::Delete}.fetch(method).new(uri)
  req['Authorization'] = "Bearer #{token}"
  req['Content-Type'] = 'application/json'
  req.body = JSON.generate(body) if body
  response = Net::HTTP.start(uri.host, uri.port, use_ssl: true) { |http| http.request(req) }
  parsed = JSON.parse(response.body) unless response.body.to_s.empty?
  unless response.code.to_i.between?(200, 299)
    abort("#{method} #{path}: HTTP #{response.code}: #{parsed}")
  end
  parsed
end

def q(value) = URI.encode_www_form_component(value)

# 1. Bundle ID. filter[identifier] is a prefix match, so compare exactly.
bundle = asc(:get, "/bundleIds?filter[identifier]=#{q(WIDGET_BUNDLE_ID)}&limit=200", token)
         .fetch('data').find { |b| b.dig('attributes', 'identifier') == WIDGET_BUNDLE_ID }
if bundle
  puts "Bundle ID #{WIDGET_BUNDLE_ID}: exists (#{bundle['id']})"
else
  bundle = asc(:post, '/bundleIds', token,
               data: {type: 'bundleIds',
                      attributes: {identifier: WIDGET_BUNDLE_ID, name: WIDGET_BUNDLE_NAME,
                                   platform: 'IOS'}}).fetch('data')
  puts "Bundle ID #{WIDGET_BUNDLE_ID}: registered (#{bundle['id']})"
end

# 2. The distribution certificate the app's own profile is signed with, so the
#    extension is signed by the same identity at export.
app_profile = asc(:get, "/profiles?filter[name]=#{q(APP_PROFILE_NAME)}&include=certificates", token)
app_profile_data = app_profile.fetch('data').find { |p| p.dig('attributes', 'name') == APP_PROFILE_NAME }
abort("Profile '#{APP_PROFILE_NAME}' not found") unless app_profile_data
cert_ids = app_profile_data.dig('relationships', 'certificates', 'data').map { |c| c['id'] }
abort("Profile '#{APP_PROFILE_NAME}' has no certificates") if cert_ids.empty?
puts "Certificates from '#{APP_PROFILE_NAME}': #{cert_ids.join(', ')}"

# 3. Widget profile: reuse an active one with the same certificates, else recreate.
existing = asc(:get, "/profiles?filter[name]=#{q(WIDGET_PROFILE_NAME)}&include=certificates,bundleId", token)
           .fetch('data').select { |p| p.dig('attributes', 'name') == WIDGET_PROFILE_NAME }
profile = existing.find do |p|
  p.dig('attributes', 'profileState') == 'ACTIVE' &&
    p.dig('relationships', 'bundleId', 'data', 'id') == bundle['id'] &&
    p.dig('relationships', 'certificates', 'data').map { |c| c['id'] }.sort == cert_ids.sort
end
(existing - [profile].compact).each do |stale|
  asc(:delete, "/profiles/#{stale['id']}", token)
  puts "Deleted stale profile #{stale['id']} (#{stale.dig('attributes', 'profileState')})"
end
if profile
  puts "Profile '#{WIDGET_PROFILE_NAME}': exists (#{profile['id']})"
else
  profile = asc(:post, '/profiles', token,
                data: {type: 'profiles',
                       attributes: {name: WIDGET_PROFILE_NAME, profileType: 'IOS_APP_STORE'},
                       relationships: {
                         bundleId: {data: {type: 'bundleIds', id: bundle['id']}},
                         certificates: {data: cert_ids.map { |id| {type: 'certificates', id: id} }}
                       }}).fetch('data')
  puts "Profile '#{WIDGET_PROFILE_NAME}': created (#{profile['id']})"
end

# 4. Install under its UUID, which is where Xcode looks for it.
content = profile.dig('attributes', 'profileContent')
content ||= asc(:get, "/profiles/#{profile['id']}", token).dig('data', 'attributes', 'profileContent')
uuid = profile.dig('attributes', 'uuid')
FileUtils.mkdir_p(PROFILES_DIR)
path = File.join(PROFILES_DIR, "#{uuid}.mobileprovision")
File.binwrite(path, Base64.decode64(content))
puts "Installed #{path}"
puts "UUID #{uuid}, expires #{profile.dig('attributes', 'expirationDate')}"

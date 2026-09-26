# Cancel a superseded iOS review submission and update the version number.
# Usage: ruby scripts/asc_prepare_version.rb OLD_SUBMISSION_ID OLD_VERSION NEW_VERSION
require 'jwt'
require 'net/http'
require 'json'
require 'openssl'
require 'uri'

APP_ID = '6799269422'
submission_id, old_version_string, version_string = ARGV
abort('Usage: asc_prepare_version.rb OLD_SUBMISSION_ID OLD_VERSION NEW_VERSION') unless submission_id && old_version_string && version_string

token = JWT.encode(
  {iss: ENV.fetch('ASC_ISSUER_ID'), aud: 'appstoreconnect-v1', exp: Time.now.to_i + 1200},
  OpenSSL::PKey::EC.new(File.read(ENV.fetch('ASC_KEY_PATH'))),
  'ES256', {kid: ENV.fetch('ASC_KEY_ID'), typ: 'JWT'}
)

def asc(method, path, token, body = nil)
  uri = URI("https://api.appstoreconnect.apple.com/v1#{path}")
  req = {get: Net::HTTP::Get, post: Net::HTTP::Post, patch: Net::HTTP::Patch}.fetch(method).new(uri)
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

submission = asc(:get, "/reviewSubmissions/#{submission_id}", token).fetch('data')
state = submission.dig('attributes', 'state')
if %w[WAITING_FOR_REVIEW IN_REVIEW].include?(state)
  asc(:patch, "/reviewSubmissions/#{submission_id}", token,
      data: {type: 'reviewSubmissions', id: submission_id, attributes: {canceled: true}})
  puts "Canceled superseded submission #{submission_id}"
elsif !%w[CANCELING COMPLETE].include?(state)
  abort("Unexpected old submission state: #{state}")
end

versions = asc(:get, "/apps/#{APP_ID}/appStoreVersions?limit=200&fields[appStoreVersions]=versionString,appStoreState,platform", token)
version = versions.fetch('data').find do |item|
  item.dig('attributes', 'platform') == 'IOS' && item.dig('attributes', 'versionString') == version_string
end
unless version
  old_version = versions.fetch('data').find do |item|
    item.dig('attributes', 'platform') == 'IOS' && item.dig('attributes', 'versionString') == old_version_string
  end
  abort("Old version #{old_version_string} not found") unless old_version
  30.times do
    old_version = asc(:get, "/appStoreVersions/#{old_version['id']}?fields[appStoreVersions]=versionString,appStoreState", token).fetch('data')
    break if %w[DEVELOPER_REJECTED READY_FOR_SALE].include?(old_version.dig('attributes', 'appStoreState'))
    sleep 2
  end
  case old_version.dig('attributes', 'appStoreState')
  when 'DEVELOPER_REJECTED'
    version = asc(:patch, "/appStoreVersions/#{old_version['id']}", token,
                  data: {type: 'appStoreVersions', id: old_version['id'],
                         attributes: {versionString: version_string,
                                      releaseType: 'AFTER_APPROVAL'}}).fetch('data')
  when 'READY_FOR_SALE'
    version = asc(:post, '/appStoreVersions', token,
                  data: {type: 'appStoreVersions',
                         attributes: {platform: 'IOS', versionString: version_string,
                                      releaseType: 'AFTER_APPROVAL', usesIdfa: false},
                         relationships: {app: {data: {type: 'apps', id: APP_ID}}}}).fetch('data')
  else
    abort('Old version has not left review')
  end
end
puts "Version #{version_string}: #{version['id']} (#{version.dig('attributes', 'appStoreState')})"

# Submit the already-uploaded Honest Signal update to App Review.
# Requires ASC_ISSUER_ID, ASC_KEY_ID, ASC_KEY_PATH and the jwt gem.
# Usage: ruby scripts/asc_submit_update.rb 4 477cb3a8-3df8-4652-870f-85cce6abe36b
require 'jwt'
require 'net/http'
require 'json'
require 'openssl'
require 'uri'

APP_ID = '6799269422'
build_number, version_id = ARGV
abort('Usage: asc_submit_update.rb BUILD_NUMBER APP_STORE_VERSION_ID') unless build_number && version_id

token = JWT.encode(
  { iss: ENV.fetch('ASC_ISSUER_ID'), aud: 'appstoreconnect-v1', exp: Time.now.to_i + 1200 },
  OpenSSL::PKey::EC.new(File.read(ENV.fetch('ASC_KEY_PATH'))),
  'ES256', { kid: ENV.fetch('ASC_KEY_ID'), typ: 'JWT' }
)

def asc(method, path, token, body = nil)
  uri = URI("https://api.appstoreconnect.apple.com/v1#{path}")
  req = { get: Net::HTTP::Get, post: Net::HTTP::Post, patch: Net::HTTP::Patch }.fetch(method).new(uri)
  req['Authorization'] = "Bearer #{token}"
  req['Content-Type'] = 'application/json'
  req.body = JSON.generate(body) if body
  response = Net::HTTP.start(uri.host, uri.port, use_ssl: true) { |http| http.request(req) }
  parsed = JSON.parse(response.body) unless response.body.to_s.empty?
  [response.code.to_i, parsed]
end

def expect(code, body, expected, action)
  return if code == expected

  details = Array(body && body['errors']).map { |e| "#{e['code']}: #{e['detail']}" }.join('; ')
  abort("#{action} failed (HTTP #{code}): #{details}")
end

code, body = asc(:get, "/builds?filter[app]=#{APP_ID}&limit=50&fields[builds]=version,processingState", token)
expect(code, body, 200, 'List builds')
build = Array(body['data']).find { |b| b.dig('attributes', 'version') == build_number }
abort("Build #{build_number} is not available") unless build
abort("Build #{build_number} is #{build.dig('attributes', 'processingState')}") unless build.dig('attributes', 'processingState') == 'VALID'
puts "Valid build: #{build['id']}"

code, body = asc(:get, "/appStoreVersions/#{version_id}?fields[appStoreVersions]=versionString,appStoreState", token)
expect(code, body, 200, 'Read version')
abort('Unexpected version') unless body.dig('data', 'attributes', 'versionString') == '1.0.2'
state = body.dig('data', 'attributes', 'appStoreState')
if state == 'WAITING_FOR_REVIEW' || state == 'IN_REVIEW'
  puts "Already submitted: #{state}"
  exit 0
end

code, body = asc(:patch, "/appStoreVersions/#{version_id}/relationships/build", token,
                 data: { type: 'builds', id: build['id'] })
expect(code, body, 204, 'Attach build')
puts 'Build attached to 1.0.2'

code, body = asc(:get, "/apps/#{APP_ID}/reviewSubmissions?filter[state]=READY_FOR_REVIEW&limit=50", token)
expect(code, body, 200, 'List draft submissions')
submission = Array(body['data']).find do |s|
  s.dig('attributes', 'platform').nil? || s.dig('attributes', 'platform') == 'IOS'
end
unless submission
  code, body = asc(:post, '/reviewSubmissions', token,
                   data: { type: 'reviewSubmissions',
                           relationships: { app: { data: { type: 'apps', id: APP_ID } } } })
  expect(code, body, 201, 'Create review submission')
  submission = body['data']
end
submission_id = submission['id']
puts "Draft submission: #{submission_id}"

code, body = asc(:get, "/reviewSubmissions/#{submission_id}/items?limit=50", token)
expect(code, body, 200, 'Read submission items')
items = Array(body['data'])
unless items.any? { |item| item.dig('relationships', 'appStoreVersion', 'data', 'id') == version_id }
  code, body = asc(:post, '/reviewSubmissionItems', token,
                   data: { type: 'reviewSubmissionItems',
                           relationships: {
                             reviewSubmission: { data: { type: 'reviewSubmissions', id: submission_id } },
                             appStoreVersion: { data: { type: 'appStoreVersions', id: version_id } }
                           } })
  expect(code, body, 201, 'Add version for review')
end

code, body = asc(:patch, "/reviewSubmissions/#{submission_id}", token,
                 data: { type: 'reviewSubmissions', id: submission_id,
                         attributes: { submitted: true } })
expect(code, body, 200, 'Submit for review')

code, body = asc(:get, "/appStoreVersions/#{version_id}?fields[appStoreVersions]=appStoreState", token)
expect(code, body, 200, 'Verify version state')
state = body.dig('data', 'attributes', 'appStoreState')
puts "Final App Store state: #{state}"
abort('Submission not confirmed') unless %w[WAITING_FOR_REVIEW IN_REVIEW].include?(state)

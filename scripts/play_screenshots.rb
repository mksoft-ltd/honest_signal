#!/usr/bin/env ruby
# Replace the en-GB phone screenshots on Google Play in a listing-only edit,
# without touching builds or tracks. Use when the screenshots change between
# releases (play_release.rb refuses to run once the build is uploaded).
require 'json'
require 'net/http'
require 'uri'
require 'googleauth'
require 'digest'

ROOT = File.expand_path('..', __dir__)
PACKAGE = 'com.froggyeye.honestsignal'
DIR = File.join(ROOT, 'android/fastlane/metadata/android/en-GB/images/phoneScreenshots')
screenshots = Dir["#{DIR}/*.png"].sort
abort "Expected 6 phone screenshots, found #{screenshots.size}" unless screenshots.size == 6

credentials = Google::Auth::ServiceAccountCredentials.make_creds(
  json_key_io: File.open(ENV.fetch('PLAY_JSON_KEY')),
  scope: 'https://www.googleapis.com/auth/androidpublisher'
)
credentials.fetch_access_token!
TOKEN = credentials.access_token
BASE = "https://androidpublisher.googleapis.com/androidpublisher/v3/applications/#{PACKAGE}"

def call_api(method, path, body = nil)
  uri = URI("#{BASE}#{path}")
  request = {'GET' => Net::HTTP::Get, 'POST' => Net::HTTP::Post,
             'DELETE' => Net::HTTP::Delete}.fetch(method).new(uri)
  request['Authorization'] = "Bearer #{TOKEN}"
  request['Content-Type'] = 'application/json'
  request.body = JSON.generate(body) if body
  response = Net::HTTP.start(uri.host, uri.port, use_ssl: true,
                             read_timeout: 600) { |http| http.request(request) }
  parsed = JSON.parse(response.body) rescue {'raw' => response.body}
  abort "#{method} #{path}: HTTP #{response.code}: #{parsed}" unless response.code.to_i.between?(200, 299)
  parsed
end

def upload(eid, file)
  uri = URI("https://androidpublisher.googleapis.com/upload/androidpublisher/v3/" \
            "applications/#{PACKAGE}/edits/#{eid}/listings/en-GB/phoneScreenshots?uploadType=media")
  request = Net::HTTP::Post.new(uri)
  request['Authorization'] = "Bearer #{TOKEN}"
  request['Content-Type'] = 'image/png'
  request.body = File.binread(file)
  response = Net::HTTP.start(uri.host, uri.port, use_ssl: true,
                             read_timeout: 600) { |http| http.request(request) }
  parsed = JSON.parse(response.body) rescue {'raw' => response.body}
  abort "upload #{file}: HTTP #{response.code}: #{parsed}" unless response.code.to_i == 200
  parsed.fetch('image')
end

edit = call_api('POST', '/edits', {})['id']
begin
  call_api('DELETE', "/edits/#{edit}/listings/en-GB/phoneScreenshots")
  screenshots.each do |file|
    image = upload(edit, file)
    puts "#{File.basename(file)} -> #{image['sha256']}"
  end
  call_api('POST', "/edits/#{edit}:commit")
  puts 'Screenshot edit committed'
rescue SystemExit, StandardError
  call_api('DELETE', "/edits/#{edit}") rescue nil
  raise
end

read = call_api('POST', '/edits', {})['id']
begin
  live = call_api('GET', "/edits/#{read}/listings/en-GB/phoneScreenshots").fetch('images')
  local = screenshots.map { |f| Digest::SHA256.file(f).hexdigest }
  ok = live.map { |i| i['sha256'] } == local
  puts "Read back #{live.size} screenshots: #{ok ? 'match local files, in order' : 'MISMATCH'}"
  exit 1 unless ok
ensure
  call_api('DELETE', "/edits/#{read}") rescue nil
end

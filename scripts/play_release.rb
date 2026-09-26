#!/usr/bin/env ruby
# Upload the current signed AAB, en-GB listing and phone screenshots as one
# Google Play production edit. A failed edit never exposes a partial listing.
require 'json'
require 'net/http'
require 'uri'
require 'googleauth'
require 'digest'

ROOT = File.expand_path('..', __dir__)
PACKAGE = 'com.froggyeye.honestsignal'
META = File.join(ROOT, 'android/fastlane/metadata/android/en-GB')
AAB = File.join(ROOT, 'build/app/outputs/bundle/release/app-release.aab')
VERSION = File.read(File.join(ROOT, 'pubspec.yaml'))[/^version:\s*([^\s+]+)\+(\d+)/, 1]
BUILD = File.read(File.join(ROOT, 'pubspec.yaml'))[/^version:\s*([^\s+]+)\+(\d+)/, 2].to_i
abort 'Release bundle missing' unless File.file?(AAB)
abort 'Invalid pubspec version' unless VERSION && BUILD.positive?

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
             'PUT' => Net::HTTP::Put, 'DELETE' => Net::HTTP::Delete}.fetch(method).new(uri)
  request['Authorization'] = "Bearer #{TOKEN}"
  request['Content-Type'] = 'application/json'
  request.body = JSON.generate(body) if body
  response = Net::HTTP.start(uri.host, uri.port, use_ssl: true,
                             read_timeout: 600) { |http| http.request(request) }
  parsed = JSON.parse(response.body) rescue {'raw' => response.body}
  abort "#{method} #{path}: HTTP #{response.code}: #{parsed}" unless response.code.to_i.between?(200, 299)
  parsed
end

def upload(eid, path, content_type, file)
  uri = URI("https://androidpublisher.googleapis.com/upload/androidpublisher/v3/" \
            "applications/#{PACKAGE}/edits/#{eid}#{path}?uploadType=media")
  request = Net::HTTP::Post.new(uri)
  request['Authorization'] = "Bearer #{TOKEN}"
  request['Content-Type'] = content_type
  request['Content-Length'] = File.size(file).to_s
  request.body_stream = File.open(file, 'rb')
  response = Net::HTTP.start(uri.host, uri.port, use_ssl: true,
                             open_timeout: 60, read_timeout: 1800,
                             write_timeout: 1800) { |http| http.request(request) }
  parsed = JSON.parse(response.body) rescue {'raw' => response.body}
  abort "upload #{file}: HTTP #{response.code}: #{parsed}" unless response.code.to_i == 200
  parsed
end

def listing(eid)
  call_api('PUT', "/edits/#{eid}/listings/en-GB", {
    language: 'en-GB',
    title: File.read("#{META}/title.txt").strip,
    shortDescription: File.read("#{META}/short_description.txt").strip,
    fullDescription: File.read("#{META}/full_description.txt").strip
  })
end

screenshots = Dir["#{META}/images/phoneScreenshots/*.png"].sort
abort "Expected five screenshots; found #{screenshots.size}" unless screenshots.size == 5
abort 'Play description exceeds 4,000 characters' if File.read("#{META}/full_description.txt").strip.length > 4000
notes = File.read("#{META}/changelogs/#{BUILD}.txt").strip

edit = call_api('POST', '/edits', {})['id']
puts "Edit #{edit}; releasing #{VERSION} (#{BUILD})"
begin
  locales = call_api('GET', "/edits/#{edit}/listings").fetch('listings', []).map { |entry| entry['language'] }
  abort "Unexpected listing locales: #{locales}" unless locales == ['en-GB']
  existing = call_api('GET', "/edits/#{edit}/bundles").fetch('bundles', [])
  abort "Build #{BUILD} already uploaded" if existing.any? { |bundle| bundle['versionCode'] == BUILD }

  bundle = upload(edit, '/bundles', 'application/octet-stream', AAB)
  abort "Uploaded build #{bundle['versionCode']} instead of #{BUILD}" unless bundle['versionCode'] == BUILD
  puts "Bundle uploaded: SHA-256 #{bundle['sha256']}"

  listing(edit)
  call_api('DELETE', "/edits/#{edit}/listings/en-GB/phoneScreenshots")
  screenshots.each do |file|
    image = upload(edit, '/listings/en-GB/phoneScreenshots', 'image/png', file).fetch('image')
    puts "Screenshot #{File.basename(file)}: #{image['sha1']}"
  end

  call_api('PUT', "/edits/#{edit}/tracks/production", {
    track: 'production', releases: [{name: "#{VERSION} (#{BUILD})",
      versionCodes: [BUILD.to_s], status: 'completed',
      releaseNotes: [{language: 'en-GB', text: notes}]}]
  })
  call_api('POST', "/edits/#{edit}:commit")
  puts 'Production edit committed'
rescue Exception
  call_api('DELETE', "/edits/#{edit}") rescue nil
  raise
end

read = call_api('POST', '/edits', {})['id']
begin
  track = call_api('GET', "/edits/#{read}/tracks/production")
  release = track.fetch('releases').first
  abort "Production read-back mismatch: #{release}" unless
    release['versionCodes'] == [BUILD.to_s] && release['status'] == 'completed'
  live = call_api('GET', "/edits/#{read}/listings/en-GB/phoneScreenshots").fetch('images')
  expected = screenshots.map { |file| Digest::SHA1.file(file).hexdigest }
  actual = live.map { |image| image['sha1'] }
  abort "Screenshot read-back mismatch: #{actual}" unless actual == expected
  puts "Verified production #{release['name']} and #{live.size} ordered screenshots"
ensure
  call_api('DELETE', "/edits/#{read}") rescue nil
end

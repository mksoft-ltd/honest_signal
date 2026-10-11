#!/usr/bin/env ruby
# Creates App Store provisioning profiles for Honest Signal (app + widget) on a
# given distribution certificate, installs them, and prints their names/UUIDs.
# Run after a new Apple Distribution certificate is issued.
#
#   ruby scripts/asc_renew_profiles.rb CERTIFICATE_ID SUFFIX
#   e.g. ruby scripts/asc_renew_profiles.rb 48CDM5Z29C 2027
#
# Idempotent: an existing profile with the target name is reused.
require 'json'
require 'net/http'
require 'jwt'
require 'openssl'
require 'fileutils'

cert_id, suffix = ARGV
abort('Usage: asc_renew_profiles.rb CERTIFICATE_ID SUFFIX') unless cert_id && suffix

TOKEN = JWT.encode(
  { iss: ENV.fetch('ASC_ISSUER_ID'), aud: 'appstoreconnect-v1', exp: Time.now.to_i + 1200 },
  OpenSSL::PKey::EC.new(File.read(ENV.fetch('ASC_KEY_PATH'))),
  'ES256', { kid: ENV.fetch('ASC_KEY_ID'), typ: 'JWT' }
)

def asc(method, path, body = nil)
  uri = URI("https://api.appstoreconnect.apple.com/v1#{path}")
  req = { get: Net::HTTP::Get, post: Net::HTTP::Post }.fetch(method).new(uri)
  req['Authorization'] = "Bearer #{TOKEN}"
  req['Content-Type'] = 'application/json'
  req.body = JSON.generate(body) if body
  res = Net::HTTP.start(uri.host, uri.port, use_ssl: true) { |h| h.request(req) }
  parsed = res.body.to_s.empty? ? {} : JSON.parse(res.body)
  abort("#{method} #{path}: HTTP #{res.code}: #{parsed}") unless res.code.to_i.between?(200, 299)
  parsed
end

PROFILES = {
  'com.froggyeye.honestsignal' => "HonestSignal App Store #{suffix}",
  'com.froggyeye.honestsignal.widget' => "HonestSignal Widget App Store #{suffix}"
}.freeze
dir = File.expand_path('~/Library/MobileDevice/Provisioning Profiles')
FileUtils.mkdir_p(dir)

PROFILES.each do |identifier, name|
  bundle = asc(:get, "/bundleIds?filter[identifier]=#{identifier}&filter[platform]=IOS")['data']
           .find { |b| b.dig('attributes', 'identifier') == identifier } || abort("No bundle id #{identifier}")
  existing = asc(:get, "/profiles?filter[name]=#{URI.encode_www_form_component(name)}")['data'].first
  profile = existing || asc(:post, '/profiles', {
    data: {
      type: 'profiles',
      attributes: { name: name, profileType: 'IOS_APP_STORE' },
      relationships: {
        bundleId: { data: { type: 'bundleIds', id: bundle['id'] } },
        certificates: { data: [{ type: 'certificates', id: cert_id }] }
      }
    }
  })['data']
  attrs = profile['attributes']
  path = File.join(dir, "#{attrs['uuid']}.mobileprovision")
  File.binwrite(path, attrs['profileContent'].unpack1('m'))
  puts "#{identifier}: \"#{name}\" #{attrs['uuid']} expires #{attrs['expirationDate']}"
end

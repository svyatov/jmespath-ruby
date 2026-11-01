# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

# Exchanges GitHub's OIDC token for a short-lived RubyGems push credential.
module TrustedPublishing
  def self.configure(owner:, env: ENV, output: $stdout)
    raise "Owner must be an immutable numeric ID" unless owner.match?(/\A\d+\z/)

    token = identity_token(env)
    output.puts("::add-mask::#{token}")
    key = exchange(token, owner)
    output.puts("::add-mask::#{key}")
    File.open(env.fetch("GITHUB_ENV"), "a", 0o600) { |file| file.puts("GEM_HOST_API_KEY=#{key}") }
  end

  def self.identity_token(env)
    uri = token_endpoint(env.fetch("ACTIONS_ID_TOKEN_REQUEST_URL"))
    request = Net::HTTP::Get.new(uri)
    request["Authorization"] = "Bearer #{env.fetch('ACTIONS_ID_TOKEN_REQUEST_TOKEN')}"
    token = request_json(uri, request).fetch("value")
    raise "Invalid GitHub identity token" unless token.is_a?(String) && token.match?(/\A[\w-]+\.[\w-]+\.[\w-]+\z/)

    token
  end

  def self.token_endpoint(url)
    uri = URI(url)
    raise "Invalid GitHub token endpoint" unless valid_endpoint?(uri)

    query = URI.decode_www_form(uri.query.to_s).reject { |pair| pair.first == "audience" }
    uri.query = URI.encode_www_form(query + [["audience", "rubygems.org"]])
    uri
  end

  def self.valid_endpoint?(uri)
    uri.scheme == "https" && uri.host&.end_with?(".actions.githubusercontent.com") && uri.userinfo.nil?
  end

  def self.exchange(token, owner)
    uri = URI("https://rubygems.org/api/v1/oidc/trusted_publisher/exchange_token")
    request = Net::HTTP::Post.new(uri, "Content-Type" => "application/json", "Accept" => "application/json")
    request.body = JSON.generate(jwt: token, owner: owner)
    key = request_json(uri, request).fetch("rubygems_api_key")
    raise "Invalid RubyGems credential" unless key.is_a?(String) && key.match?(/\Arubygems_[A-Za-z0-9]+\z/)

    key
  end

  def self.request_json(uri, request)
    response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 10, read_timeout: 30) do |http|
      http.request(request)
    end
    raise "Token request failed (HTTP #{response.code})" unless response.code.to_i.between?(200, 299)

    JSON.parse(response.body)
  rescue JSON::ParserError
    raise "Invalid JSON in token response", cause: nil
  end
end

TrustedPublishing.configure(owner: ENV.fetch("RUBYGEMS_OWNER_ID")) if $PROGRAM_NAME == __FILE__

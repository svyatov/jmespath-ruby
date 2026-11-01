# frozen_string_literal: true

require "stringio"
require "tmpdir"
require_relative "../../script/configure_trusted_publishing"

RSpec.describe "Trusted publishing credentials" do
  it "exchanges the GitHub token with the immutable RubyGems owner and masks the resulting key" do
    Dir.mktmpdir do |directory|
      path = File.join(directory, "environment")
      env = {
        "ACTIONS_ID_TOKEN_REQUEST_URL" => "https://tokens.actions.githubusercontent.com/token?existing=1",
        "ACTIONS_ID_TOKEN_REQUEST_TOKEN" => "request-token",
        "GITHUB_ENV" => path
      }
      requests = []
      client = instance_double(Net::HTTP)
      allow(Net::HTTP).to receive(:start).and_yield(client)
      allow(client).to receive(:request) do |request|
        requests << request
        body = requests.length == 1 ? { value: "header.payload.signature" } : { rubygems_api_key: "rubygems_synthetic" }
        instance_double(Net::HTTPResponse, code: "200", body: JSON.generate(body))
      end
      output = StringIO.new
      TrustedPublishing.configure(owner: "71752", env: env, output: output)

      expect(requests.first.path).to eq("/token?existing=1&audience=rubygems.org")
      expect(requests.first["Authorization"]).to eq("Bearer request-token")
      expect(requests.last.path).to eq("/api/v1/oidc/trusted_publisher/exchange_token")
      expect(JSON.parse(requests.last.body)).to eq("jwt" => "header.payload.signature", "owner" => "71752")
      expect(File.read(path)).to eq("GEM_HOST_API_KEY=rubygems_synthetic\n")
      expect(output.string).to eq("::add-mask::header.payload.signature\n::add-mask::rubygems_synthetic\n")
    end
  end

  it "rejects an insecure or unrelated token endpoint before sending credentials" do
    %w[http://tokens.actions.githubusercontent.com/token https://example.com/token].each do |url|
      env = { "ACTIONS_ID_TOKEN_REQUEST_URL" => url }
      expect(Net::HTTP).not_to receive(:start)
      expect { TrustedPublishing.configure(owner: "71752", env: env) }.to raise_error(/Invalid GitHub token endpoint/)
    end
  end

  it "rejects an invalid owner before requesting a token" do
    expect(Net::HTTP).not_to receive(:start)
    expect { TrustedPublishing.configure(owner: "svyatov") }.to raise_error(/immutable numeric ID/)
  end

  it "does not print a server error body that may contain credentials" do
    client = instance_double(Net::HTTP)
    allow(Net::HTTP).to receive(:start).and_yield(client)
    allow(client).to receive(:request).and_return(instance_double(Net::HTTPResponse, code: "403", body: "secret-token"))
    env = {
      "ACTIONS_ID_TOKEN_REQUEST_URL" => "https://tokens.actions.githubusercontent.com/token",
      "ACTIONS_ID_TOKEN_REQUEST_TOKEN" => "request-token"
    }
    expect { TrustedPublishing.configure(owner: "71752", env: env) }.to raise_error("Token request failed (HTTP 403)")
  end

  it "rejects malformed credentials before exporting them to later workflow steps" do
    client = instance_double(Net::HTTP)
    allow(Net::HTTP).to receive(:start).and_yield(client)
    responses = [{ value: "header.payload.signature" }, { rubygems_api_key: "rubygems_key\nOTHER=value" }]
    allow(client).to receive(:request) do
      instance_double(Net::HTTPResponse, code: "200", body: JSON.generate(responses.shift))
    end
    env = {
      "ACTIONS_ID_TOKEN_REQUEST_URL" => "https://tokens.actions.githubusercontent.com/token",
      "ACTIONS_ID_TOKEN_REQUEST_TOKEN" => "request-token"
    }
    expect { TrustedPublishing.configure(owner: "71752", env: env, output: StringIO.new) }
      .to raise_error(/Invalid RubyGems credential/)
  end

  it "does not retain an invalid response body in the exception cause" do
    client = instance_double(Net::HTTP)
    allow(Net::HTTP).to receive(:start).and_yield(client)
    allow(client).to receive(:request).and_return(instance_double(Net::HTTPResponse, code: "200", body: "secret-token"))
    env = {
      "ACTIONS_ID_TOKEN_REQUEST_URL" => "https://tokens.actions.githubusercontent.com/token",
      "ACTIONS_ID_TOKEN_REQUEST_TOKEN" => "request-token"
    }
    expect { TrustedPublishing.configure(owner: "71752", env: env) }.to raise_error do |error|
      expect(error.message).to eq("Invalid JSON in token response")
      expect(error.cause).to be_nil
    end
  end
end

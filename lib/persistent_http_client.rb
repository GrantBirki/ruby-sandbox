# frozen_string_literal: true

require "logger"
require "net/http/persistent"

module HTTP
  class Client
    VERB_MAP = {
      head: Net::HTTP::Head,
      get: Net::HTTP::Get,
      post: Net::HTTP::Post,
      put: Net::HTTP::Put,
      delete: Net::HTTP::Delete,
      patch: Net::HTTP::Patch
    }.freeze

    # Expose the HTTP client so that we can customize client-level settings,
    # such as timeouts, etc.
    attr_accessor :http

    # :param endpoint: endpoint to send requests to
    # :param name: name of the client
    def initialize(endpoint, name: "http-client", log: nil)
      @uri = URI.parse(endpoint)
      @name = name
      @http = create_http_client
      @log = log || create_logger
    end

    def head(path, headers: {}, params: {})
      request :head, path, headers:, params:
    end

    def get(path, headers: {}, params: {})
      request :get, path, headers:, params:
    end

    def post(path, headers: {}, params: {})
      request :post, path, headers:, params:
    end

    def put(path, headers: {}, params: {})
      request :put, path, headers:, params:
    end

    def delete(path, headers: {}, params: {})
      request :delete, path, headers:, params:
    end

    def patch(path, headers: {}, params: {})
      request :patch, path, headers:, params:
    end

    private

    def create_logger
      Logger.new($stdout, level: ENV.fetch("LOG_LEVEL", "INFO").upcase)
    end

    # Create a persistent HTTP client
    def create_http_client
      http = Net::HTTP::Persistent.new(name: @name)
      http.verify_mode = OpenSSL::SSL::VERIFY_PEER if @uri.scheme == "https"
      http
    end

    # :param method: HTTP method
    # :param path: path to send request to
    # :param headers: headers to send with request
    # :param params: params to send with request
    def build_request(method, path, headers: {}, params: {})
      raise ArgumentError, "Querystring must be sent via `params` or `path` but not both." if path.include?("?") && !params.empty?

      normalized_headers = {}

      headers.each do |key, value|
        normalized_key = key.downcase
        raise ArgumentError, "Duplicate headers detected." if normalized_headers.key?(normalized_key)

        normalized_headers[normalized_key] = value
      end

      case method
      when :get, :head
        full_path = encode_path_params(path, params)
        request = VERB_MAP[method].new(full_path, headers)
      else
        headers["content-type"] = "application/json" unless headers.key?("content-type")

        request = VERB_MAP[method].new(path, headers)
        request.body = params.to_json
      end

      request
    end

    # :param method: HTTP method
    # :param path: path to send request to
    # :param headers: headers to send with request
    # :param params: params to send with request
    # :return: response from request
    def request(method, path, headers: {}, params: {})
      req = build_request(method, path, headers:, params:)

      begin
        @http.request(@uri, req)
      rescue Net::HTTP::Persistent::Error, Net::OpenTimeout, Net::ReadTimeout, Errno::ECONNRESET => e
        @log.debug("connection failed: #{e.message} - rebuilding http client")
        @http = create_http_client
        @http.request(@uri, req)
      end
    end

    # A helper method to encode path params
    # :param path: path to encode params into
    # :param params: params to encode
    # :return: encoded path
    def encode_path_params(path, params)
      return path if params.nil? || params.empty?

      encoded = URI.encode_www_form(params)
      [path, encoded].join("?")
    end
  end
end

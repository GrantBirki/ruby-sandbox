# frozen_string_literal: true

# Example usage:
#
# # Basic usage
# client = HTTP::Client.new("https://api.example.com")
# response = client.get("/users")
# puts response.body
#
# # With headers and query parameters
# response = client.get("/users",
#   headers: {"Authorization" => "Bearer token123"},
#   params: {status: "active", limit: 10})
#
# # POST JSON data
# response = client.post("/users",
#   headers: {"X-Custom-Header" => "value"},
#   params: {name: "John Doe", email: "john@example.com"})
#
# # With custom timeouts
# client = HTTP::Client.new("https://api.example.com",
#   open_timeout: 5,     # connection establishment timeout (seconds)
#   read_timeout: 10,    # response read timeout (seconds)
#   keep_alive_timeout: 30  # how long to keep idle connections open (seconds)
# )

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

    # Expose the HTTP client so that we can customize client-level settings
    attr_accessor :http

    # Create a new persistent HTTP client
    #
    # @param endpoint [String] Endpoint URL to send requests to
    # @param name [String] Name for the client (used in logs)
    # @param log [Logger] Custom logger instance (optional)
    # @param open_timeout [Integer] Timeout in seconds for connection establishment
    # @param read_timeout [Integer] Timeout in seconds for reading response
    # @param keep_alive_timeout [Integer] How long to keep idle connections open in seconds
    # @param max_retries [Integer] Maximum number of retries on connection failures
    def initialize(
      endpoint,
      name: "http-client",
      log: nil,
      open_timeout: 5,
      read_timeout: 60,
      keep_alive_timeout: 30,
      max_retries: 1
    )
      @uri = URI.parse(endpoint)
      @name = name
      @open_timeout = open_timeout
      @read_timeout = read_timeout
      @keep_alive_timeout = keep_alive_timeout
      @max_retries = max_retries
      @http = create_http_client
      @log = log || create_logger
    end

    def head(path, headers: {}, params: {})
      request(:head, path, headers: headers, params: params)
    end

    def get(path, headers: {}, params: {})
      request(:get, path, headers: headers, params: params)
    end

    def post(path, headers: {}, params: {})
      request(:post, path, headers: headers, params: params)
    end

    def put(path, headers: {}, params: {})
      request(:put, path, headers: headers, params: params)
    end

    def delete(path, headers: {}, params: {})
      request(:delete, path, headers: headers, params: params)
    end

    def patch(path, headers: {}, params: {})
      request(:patch, path, headers: headers, params: params)
    end

    private

    def create_logger
      Logger.new($stdout, level: ENV.fetch("LOG_LEVEL", "INFO").upcase)
    end

    # Create a persistent HTTP client with configured timeouts and SSL settings
    def create_http_client
      http = Net::HTTP::Persistent.new(name: @name)

      # Configure SSL if using HTTPS
      if @uri.scheme == "https"
        http.verify_mode = OpenSSL::SSL::VERIFY_PEER
        http.ca_file = ENV["SSL_CERT_FILE"] if ENV["SSL_CERT_FILE"]
      end

      # Configure timeouts
      http.open_timeout = @open_timeout
      http.read_timeout = @read_timeout
      http.idle_timeout = @keep_alive_timeout

      http
    end

    # Build an HTTP request with proper headers and parameters
    #
    # @param method [Symbol] HTTP method (:get, :post, etc)
    # @param path [String] Request path
    # @param headers [Hash] Request headers
    # @param params [Hash] Request parameters or body
    # @return [Net::HTTP::Request] The prepared request object
    def build_request(method, path, headers: {}, params: {})
      raise ArgumentError, "Querystring must be sent via `params` or `path` but not both." if path.include?("?") && !params.empty?

      # Normalize headers (convert keys to lowercase)
      normalized_headers = {}
      headers.each do |key, value|
        normalized_key = key.downcase
        raise ArgumentError, "Duplicate headers detected." if normalized_headers.key?(normalized_key)
        normalized_headers[normalized_key] = value
      end

      case method
      when :get, :head
        full_path = encode_path_params(path, params)
        request = VERB_MAP[method].new(full_path)
      else
        request = VERB_MAP[method].new(path)
        normalized_headers["content-type"] = "application/json" unless normalized_headers.key?("content-type")
        request.body = params.to_json
      end

      # Add normalized headers to request
      normalized_headers.each { |key, value| request[key] = value }

      request
    end

    # Execute an HTTP request with automatic retries on connection failures
    #
    # @param method [Symbol] HTTP method (:get, :post, etc)
    # @param path [String] Request path
    # @param headers [Hash] Request headers
    # @param params [Hash] Request parameters or body
    # @return [Net::HTTPResponse] The HTTP response
    def request(method, path, headers: {}, params: {})
      req = build_request(method, path, headers: headers, params: params)
      retries = 0

      begin
        @http.request(@uri, req)
      rescue Net::HTTP::Persistent::Error, Net::OpenTimeout, Net::ReadTimeout, Errno::ECONNRESET => e
        retries += 1
        if retries <= @max_retries
          @log.debug("Connection failed: #{e.message} - rebuilding HTTP client (retry #{retries}/#{@max_retries})")
          @http = create_http_client
          retry
        else
          @log.error("Connection failed after #{retries} retries: #{e.message}")
          raise
        end
      end
    end

    # Encode path parameters into a URL query string
    #
    # @param path [String] The base path
    # @param params [Hash] Parameters to encode
    # @return [String] The path with encoded parameters
    def encode_path_params(path, params)
      return path if params.nil? || params.empty?

      encoded = URI.encode_www_form(params)
      [path, encoded].join("?")
    end
  end
end

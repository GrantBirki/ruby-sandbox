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
#   keep_alive_timeout: 30,  # how long to keep idle connections open (seconds)
#   request_timeout: 15  # overall request timeout (seconds)
# )
#
# # With default headers (applied to all requests)
# client = HTTP::Client.new("https://api.example.com",
#   default_headers: {
#     "User-Agent" => "MyApp/1.0",
#     "Authorization" => "Bearer default-token"
#   }
# )
# # Request-specific headers will override defaults with the same key
# response = client.get("/users", headers: {"Authorization" => "Bearer override-token"})

require "logger"
require "net/http/persistent"
require "timeout"

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
    attr_accessor :http, :default_headers

    # Create a new persistent HTTP client
    #
    # @param endpoint [String] Endpoint URL to send requests to
    # @param name [String] Name for the client (used in logs)
    # @param log [Logger] Custom logger instance (optional)
    # @param open_timeout [Integer] Timeout in seconds for connection establishment
    # @param read_timeout [Integer] Timeout in seconds for reading response
    # @param keep_alive_timeout [Integer] How long to keep idle connections open in seconds
    # @param request_timeout [Integer, nil] Overall timeout for the entire request (nil for no timeout)
    # @param max_retries [Integer] Maximum number of retries on connection failures
    # @param default_headers [Hash] Default headers to include in all requests
    # @param pool_size [Integer] Connection pool size for the persistent HTTP client
    def initialize(
      endpoint,
      name: "http-client",
      log: nil,
      open_timeout: 5,
      read_timeout: 60,
      keep_alive_timeout: 30,
      request_timeout: nil,
      max_retries: 1,
      default_headers: {},
      pool_size: 5
    )
      @uri = URI.parse(endpoint)
      @name = name
      @open_timeout = open_timeout
      @read_timeout = read_timeout
      @keep_alive_timeout = keep_alive_timeout
      @request_timeout = request_timeout
      @max_retries = max_retries
      @pool_size = pool_size
      @default_headers = normalize_headers(default_headers)
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

    # Set or update default headers
    #
    # @param headers [Hash] Headers to set as default
    def set_default_headers(headers)
      @default_headers = normalize_headers(headers)
    end

    # Method to explicitly close all persistent connections
    def close!
      @http.shutdown
    end

    # Method to check connection status
    def alive?(path = "/")
      begin
        get(path, headers: { "Connection" => "close" })
        true
      rescue => e
        @log.debug("Connection check failed: #{e.message}")
        false
      end
    end

    private

    def create_logger
      Logger.new($stdout, level: ENV.fetch("LOG_LEVEL", "INFO").upcase)
    end

    # Create a persistent HTTP client with configured timeouts and SSL settings
    def create_http_client
      http = Net::HTTP::Persistent.new(name: @name, pool_size: @pool_size)

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

    # Normalize headers by converting keys to lowercase
    #
    # @param headers [Hash] Headers to normalize
    # @return [Hash] Normalized headers with lowercase keys
    def normalize_headers(headers)
      result = {}
      headers.each do |key, value|
        normalized_key = key.to_s.downcase
        result[normalized_key] = value
      end
      result
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

      # Merge and normalize headers (default headers < request-specific headers)
      normalized_headers = @default_headers.dup
      normalize_headers(headers).each do |key, value|
        normalized_headers[key] = value
      end

      case method
      when :get, :head
        full_path = encode_path_params(path, params)
        request = VERB_MAP[method].new(full_path)
      else
        request = VERB_MAP[method].new(path)

        if !params.empty?
          if !normalized_headers.key?("content-type")
            normalized_headers["content-type"] = "application/json"
            request.body = params.to_json
          elsif normalized_headers["content-type"].include?("x-www-form-urlencoded")
            request.body = URI.encode_www_form(params)
          elsif params.is_a?(String)
            request.body = params
          else
            request.body = params.to_json
          end
        end
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
      start_time = Time.now

      begin
        response = if @request_timeout
                     Timeout.timeout(@request_timeout) do
                       @http.request(@uri, req)
                     end
                    else
                      @http.request(@uri, req)
                    end

        duration = Time.now - start_time
        @log.debug("Request completed: method=#{method}, path=#{path}, status=#{response.code}, duration=#{duration.round(3)}s")
        response
      rescue Timeout::Error => e
        duration = Time.now - start_time
        @log.error("Request timed out after #{duration.round(3)}s: method=#{method}, path=#{path}")
        raise
      rescue Net::HTTP::Persistent::Error, Net::OpenTimeout, Net::ReadTimeout, Errno::ECONNRESET => e
        retries += 1
        if retries <= @max_retries
          @log.debug("Connection failed: #{e.message} - rebuilding HTTP client (retry #{retries}/#{@max_retries})")
          @http = create_http_client
          retry
        else
          duration = Time.now - start_time
          @log.error("Connection failed after #{retries} retries (#{duration.round(3)}s): #{e.message}")
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

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
#   idle_timeout: 30,  # how long to keep idle connections open (seconds)
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

# Benefits:
#
# 1. Reuse connections for multiple requests
# 2. Automatically rebuild the connection if it is closed by the server
# 3. Automatically retry requests on connection failures if max_retries is set to a value >1
# 4. Easy to use and configure
# 5. Supports timeouts for the entire request (open_timeout + read_timeout) and for idle connections (idle_timeout)

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
    # @param default_headers [Hash] Default headers to include in all requests
    # @param request_timeout [Integer, nil] Overall timeout for the entire request (nil for no timeout)
    # @param max_retries [Integer] Maximum number of retries on connection failures
    # @param open_timeout [Integer] Timeout in seconds for connection establishment
    # @param read_timeout [Integer] Timeout in seconds for reading response
    # @param idle_timeout [Integer] How long to keep idle connections open in seconds (maps to keep_alive)
    # @param **options [Hash] Additional options passed directly to Net::HTTP::Persistent
    def initialize(
      endpoint,
      name: "http-client",
      log: nil,
      default_headers: {},
      request_timeout: nil,
      max_retries: 1,
      # Default timeouts
      open_timeout: 5,
      read_timeout: 60,
      idle_timeout: 30,
      # Pass through any other options to Net::HTTP::Persistent
      **options
    )
      @uri = URI.parse(endpoint)
      @name = name
      @request_timeout = request_timeout
      @max_retries = max_retries
      @default_headers = normalize_headers(default_headers)
      @log = log || create_logger

      # Create options hash for Net::HTTP::Persistent
      persistent_options = {
        name: @name,
        open_timeout: open_timeout,
        read_timeout: read_timeout,
        idle_timeout: idle_timeout
      }

      # Merge any additional options passed through
      persistent_options.merge!(options)

      @http = create_http_client(persistent_options)
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

    private

    def create_logger
      Logger.new($stdout, level: ENV.fetch("LOG_LEVEL", "INFO").upcase)
    end

    # Create a persistent HTTP client with configured timeouts and SSL settings
    def create_http_client(options)
      # Extract only the parameters accepted by Net::HTTP::Persistent.new
      constructor_options = {}
      constructor_options[:name] = options.delete(:name) if options.key?(:name)
      constructor_options[:proxy] = options.delete(:proxy) if options.key?(:proxy)
      constructor_options[:pool_size] = options.delete(:pool_size) if options.key?(:pool_size)

      # Create the HTTP client with only the supported constructor options
      http = Net::HTTP::Persistent.new(**constructor_options)

      # Apply timeouts and other options as attributes after initialization
      http.open_timeout = options[:open_timeout] if options.key?(:open_timeout)
      http.read_timeout = options[:read_timeout] if options.key?(:read_timeout)
      http.idle_timeout = options[:idle_timeout] if options.key?(:idle_timeout)

      # Configure SSL if using HTTPS
      if @uri.scheme == "https"
        http.verify_mode = OpenSSL::SSL::VERIFY_PEER
        http.ca_file = ENV["SSL_CERT_FILE"] if ENV["SSL_CERT_FILE"]
      end

      # Apply any other options that might be supported as attributes
      options.each do |key, value|
        setter = "#{key}="
        if http.respond_to?(setter)
          http.send(setter, value) # rubocop:disable GitHub/AvoidObjectSendWithDynamicMethod
        else
          @log.debug("Ignoring unsupported option: #{key}")
        end
      end

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
        @log.debug("Request completed: method=#{method}, path=#{path}, status=#{response.code}, duration=#{format_duration_ms(duration)}")
        response
      rescue Timeout::Error => e
        duration = Time.now - start_time
        @log.error("Request timed out after #{format_duration_ms(duration)}: method=#{method}, path=#{path}")
        raise
      rescue Net::HTTP::Persistent::Error, Net::OpenTimeout, Net::ReadTimeout, Errno::ECONNRESET => e
        retries += 1
        if retries <= @max_retries
          @log.debug("Connection failed: #{e.message} - rebuilding HTTP client (retry #{retries}/#{@max_retries})")
          @http = create_http_client
          retry
        else
          duration = Time.now - start_time
          @log.error("Connection failed after #{retries} retries (#{format_duration_ms(duration)}): #{e.message}")
          raise
        end
      end
    end

    # Format duration in milliseconds
    #
    # @param duration [Float] Duration in seconds
    # @return [String] Formatted duration in milliseconds
    def format_duration_ms(duration)
      "#{(duration * 1000).round(2)} ms"
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

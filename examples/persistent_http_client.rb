# frozen_string_literal: true

# USAGE:
# 1. Start the server: `script/server`
# 2. Run this script: `LOG_LEVEL=DEBUG bundle exec ruby examples/persistent_http_client.rb`
# 3. Observe the output

require_relative "../lib/persistent_http_client"
require "benchmark"

# Helper method to time and execute a request
def timed_get_request(client, path)
  time = Benchmark.realtime do
    response = client.get(path)
    puts "Response Body: #{response.body}"
    puts "Response Code: #{response.code}"
  end
  puts "Request Time: #{(time * 1000).round(2)} ms"
end

# Create a single persistent HTTP client
# This client will reuse connections for all requests and rebuild the client automatically
# if the connection is closed by the server
# This is useful for long-lived clients, such as a CLI or a background job
# This helps because building a new client for each request sends extra TCP packets
# By reusing connections, we can reduce the number of TCP packets sent and improve performance
client = HTTP::Client.new("http://127.0.0.1:8080")

# Perform multiple requests
3.times do
  timed_get_request(client, "/")
end

# Sleep for 30 seconds to allow the server to close a connection on us
puts "\nSleeping for 30 seconds...\n"
sleep 30

alive = client.alive?
puts "Client is alive: #{alive}"

# Make another few requests and see if the client automatically rebuilds the connection
3.times do
  timed_get_request(client, "/")
end

# now close the client
client.close!

# The clean example of using this client looks like this:
# client = HTTP::Client.new("http://127.0.0.1:8080")
# response = client.get("/")
# puts "Response Body: #{response.body}"
# puts "Response Code: #{response.code}"

# The results of using persistent connections are as follows:

# $ LOG_LEVEL=DEBUG bundle exec ruby examples/persistent_http_client.rb
# Response Body: Hello, world!
# Response Code: 200
# Request Time: 2.29 ms (first request, connection is established)
# Response Body: Hello, world!
# Response Code: 200
# Request Time: 0.69 ms (subsequent requests reuse the connection)
# Response Body: Hello, world!
# Response Code: 200
# Request Time: 0.67 ms (subsequent requests reuse the connection)

# Sleeping for 30 seconds... (this will cause our connection to be closed as stale from the server)

# Response Body: Hello, world!
# Response Code: 200
# Request Time: 2.93 ms (first request, connection is re-established)
# Response Body: Hello, world!
# Response Code: 200
# Request Time: 1.32 ms (subsequent requests reuse the re-established connection)
# Response Body: Hello, world!
# Response Code: 200
# Request Time: 0.84 ms (subsequent requests reuse the re-established connection)

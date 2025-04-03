# frozen_string_literal: true

# $ bundle exec ruby benchmarks/http_clients.rb
# Benchmarking Persistent HTTP Client...
# Request 1000: Response Code: 200
# Request 2000: Response Code: 200
# Request 3000: Response Code: 200
# Request 4000: Response Code: 200
# Request 5000: Response Code: 200
# Request 6000: Response Code: 200
# Request 7000: Response Code: 200
# Request 8000: Response Code: 200
# Request 9000: Response Code: 200
# Request 10000: Response Code: 200
# Total Time (Persistent HTTP Client): 2052.04 ms
# Benchmarking Net::HTTP...
# Request 1000: Response Code: 200
# Request 2000: Response Code: 200
# Request 3000: Response Code: 200
# Request 4000: Response Code: 200
# Request 5000: Response Code: 200
# Request 6000: Response Code: 200
# Request 7000: Response Code: 200
# Request 8000: Response Code: 200
# Request 9000: Response Code: 200
# Request 10000: Response Code: 200
# Total Time (Net::HTTP): 8005.07 ms
# Persistent HTTP Client is 3.9x faster than Net::HTTP

require_relative "../lib/persistent_http_client"
require "net/http"
require "benchmark"

HOST = "http://127.0.0.1:8080"

ATTEMPTS = 10_000

# Benchmark 10,000 requests using the persistent HTTP client
def benchmark_persistent_http_client
  client = HTTP::Client.new(HOST)
  total_time = Benchmark.realtime do
    ATTEMPTS.times do |i|
      response = client.get("/")
      puts "Request #{i + 1}: Response Code: #{response.code}" if (i + 1) % 1000 == 0
    end
  end
  client.close!
  puts "Total Time (Persistent HTTP Client): #{(total_time * 1000).round(2)} ms"
  return total_time
end

puts "Benchmarking Persistent HTTP Client..."
persistent_client_time = benchmark_persistent_http_client

# Benchmark 10,000 requests using Net::HTTP with new connections
def benchmark_net_http
  uri = URI(HOST)
  total_time = Benchmark.realtime do
    ATTEMPTS.times do |i|
      response = Net::HTTP.get_response(uri)
      puts "Request #{i + 1}: Response Code: #{response.code}" if (i + 1) % 1000 == 0
    end
  end
  puts "Total Time (Net::HTTP): #{(total_time * 1000).round(2)} ms"
  return total_time
end

puts "Benchmarking Net::HTTP..."
net_http_time = benchmark_net_http

puts "Persistent HTTP Client is #{(net_http_time / persistent_client_time).round(2)}x faster than Net::HTTP"

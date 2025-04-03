# frozen_string_literal: true

# $ bundle exec ruby benchmarks/http_clients.rb
# This script benchmarks multiple HTTP clients for 10,000 requests to a Sinatra server running on localhost.
# Comparison Results:
# Persistent HTTP Client is 0.95x faster than Net::HTTP
# Persistent HTTP Client is 1.18x faster than Faraday

require_relative "../lib/persistent_http_client"
require "faraday/net_http_persistent"
require "net/http"
require "faraday"
require "httparty"
require "benchmark"

HOST = "http://127.0.0.1:8080"
ATTEMPTS = 30_000

# Helper method to print benchmark results
def print_results(client_name, total_time)
  puts "Total Time (#{client_name}): #{(total_time * 1000).round(2)} ms"
end

# Benchmark Persistent HTTP Client
def benchmark_persistent_http_client
  client = HTTP::Client.new(HOST)
  total_time = Benchmark.realtime do
    ATTEMPTS.times do |i|
      response = client.get("/")
      puts "Request #{i + 1}: Response Code: #{response.code}" if (i + 1) % 1000 == 0
    end
  end
  client.close!
  print_results("Persistent HTTP Client", total_time)
  total_time
end

# Benchmark Net::HTTP
def benchmark_net_http
  uri = URI(HOST)
  total_time = Benchmark.realtime do
    Net::HTTP.start(uri.host, uri.port) do |http|
      ATTEMPTS.times do |i|
        response = http.get(uri)
        puts "Request #{i + 1}: Response Code: #{response.code}" if (i + 1) % 1000 == 0
      end
    end
  end
  print_results("Net::HTTP", total_time)
  total_time
end

# Benchmark Faraday
def benchmark_faraday
  connection = Faraday.new(url: HOST) do |faraday|
    faraday.adapter :net_http_persistent
  end
  total_time = Benchmark.realtime do
    ATTEMPTS.times do |i|
      response = connection.get("/")
      puts "Request #{i + 1}: Response Code: #{response.status}" if (i + 1) % 1000 == 0
    end
  end
  print_results("Faraday", total_time)
  total_time
end

# does not even support persistent connections
# # Benchmark HTTParty
# def benchmark_httparty
#   total_time = Benchmark.realtime do
#     ATTEMPTS.times do |i|
#       response = HTTParty.get(HOST)
#       puts "Request #{i + 1}: Response Code: #{response.code}" if (i + 1) % 1000 == 0
#     end
#   end
#   print_results("HTTParty", total_time)
#   total_time
# end

# Run all benchmarks
puts "Benchmarking Faraday..."
faraday_time = benchmark_faraday
sleep 2

puts "Benchmarking Persistent HTTP Client..."
persistent_client_time = benchmark_persistent_http_client
sleep 2

puts "Benchmarking Net::HTTP..."
net_http_time = benchmark_net_http
sleep 2

# puts "Benchmarking HTTParty..."
# httparty_time = benchmark_httparty
# sleep 2

# Compare results
puts "\nComparison Results:"
puts "Persistent HTTP Client is #{(net_http_time / persistent_client_time).round(2)}x faster than Net::HTTP"
puts "Persistent HTTP Client is #{(faraday_time / persistent_client_time).round(2)}x faster than Faraday"
# puts "Persistent HTTP Client is #{(httparty_time / persistent_client_time).round(2)}x faster than HTTParty"

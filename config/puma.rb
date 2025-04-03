# frozen_string_literal: true

require "time"
require "json"

bind "tcp://0.0.0.0:8080"
# single mode: https://github.com/puma/puma/blob/master/docs/deployment.md#single-vs-cluster-mode
workers 0

log_requests true

# Set keep-alive timeout to 20 seconds
# https://github.com/puma/puma/blob/b836667e9fde7e982880d28e03da9c0f87085de2/lib/puma/dsl.rb#L347-L358
persistent_timeout 20

log_formatter do |msg|
  timestamp = Time.now.strftime("%Y-%m-%dT%H:%M:%S.%L%z")
  {
    time: timestamp,
    level: "INFO",
    progname: "puma",
    msg: msg.rstrip,
  }.to_json
end

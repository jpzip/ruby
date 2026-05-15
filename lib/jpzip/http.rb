# frozen_string_literal: true

require "net/http"
require "uri"

module Jpzip
  # Internal HTTP helpers. Pinned to the Ruby stdlib (net/http) so the gem
  # has zero runtime dependencies.
  module Http
    MAX_ATTEMPTS = 3
    BASE_BACKOFF = 0.2
    DEFAULT_TIMEOUT = 30 # seconds

    # Result wraps an HTTP response: +body+ (String or nil) and +status+ (Integer).
    Result = Struct.new(:body, :status, keyword_init: true)

    # Get fetches +url+ with bounded retries on 5xx / network failures.
    #
    # Returns a Result where +status+ is the HTTP status code. On 404 +body+
    # is nil so callers can distinguish "absent" from "fetch error". On
    # repeated failure this raises the last error encountered.
    def self.get(url, http_client: nil, sleeper: nil)
      uri = URI(url)
      last_error = nil

      MAX_ATTEMPTS.times do |attempt|
        if attempt.positive?
          delay = BASE_BACKOFF * (2**attempt)
          (sleeper || method(:sleep)).call(delay)
        end

        begin
          response = perform_request(uri, http_client)
          status = response.code.to_i

          return Result.new(body: nil, status: 404) if status == 404

          if status >= 500
            last_error = HttpError.new("jpzip: #{url} returned #{status}")
            next
          end

          if status >= 400
            raise HttpError, "jpzip: #{url} returned #{status}"
          end

          return Result.new(body: response.body, status: status)
        rescue HttpError
          raise
        rescue StandardError => e
          last_error = e
          next
        end
      end

      raise(last_error || HttpError.new("jpzip: #{url} failed after #{MAX_ATTEMPTS} attempts"))
    end

    def self.perform_request(uri, http_client)
      if http_client
        return http_client.call(uri)
      end

      Net::HTTP.start(
        uri.host,
        uri.port,
        use_ssl: uri.scheme == "https",
        open_timeout: DEFAULT_TIMEOUT,
        read_timeout: DEFAULT_TIMEOUT
      ) do |http|
        req = Net::HTTP::Get.new(uri.request_uri)
        req["Accept"] = "application/json"
        req["Accept-Encoding"] = "gzip"
        http.request(req)
      end
    end

    # HttpError signals a non-retryable HTTP failure (4xx other than 404, or
    # exhausted retries on 5xx).
    class HttpError < StandardError; end
  end
end

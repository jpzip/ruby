# frozen_string_literal: true

require_relative "jpzip/version"
require_relative "jpzip/types"
require_relative "jpzip/cache"
require_relative "jpzip/http"
require_relative "jpzip/client"

# Jpzip is the Ruby SDK for the jpzip postal-code dataset
# (https://jpzip.nadai.dev). The SDK fetches normalized JSON from the CDN,
# keeps a per-prefix in-memory LRU, and optionally backs that with a
# user-supplied persistent cache.
module Jpzip
  class << self
    # Returns true iff +str+ is a syntactically valid 7-digit zipcode
    # (no network call).
    def valid_zipcode?(str)
      ZIP_REGEX.match?(str.to_s)
    end

    # Convenience shortcuts delegating to a process-wide default Client.
    # The singleton uses L1 only — for L2 caches construct your own Client.
    def lookup(zipcode)
      default_client.lookup(zipcode)
    end

    def lookup_group(prefix)
      default_client.lookup_group(prefix)
    end

    def lookup_all
      default_client.lookup_all
    end

    def preload(scope)
      default_client.preload(scope)
    end

    def meta
      default_client.meta
    end

    # Replace the singleton — mainly for tests.
    def reset_default_client!
      @default_client = nil
    end

    # Override the singleton with a configured Client. Useful when the app
    # wants to share an L2 cache through the module-level helpers.
    def configure(**opts)
      @default_client = Client.new(**opts)
    end

    private

    def default_client
      @default_client ||= Client.new
    end
  end
end

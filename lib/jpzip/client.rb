# frozen_string_literal: true

require "json"
require "monitor"

require_relative "cache"
require_relative "http"
require_relative "types"
require_relative "version"

module Jpzip
  ZIP_REGEX = /\A\d{7}\z/.freeze
  PREFIX_REGEX = /\A\d{1,3}\z/.freeze

  # InvalidPrefixError is raised when LookupGroup/Preload receive a prefix
  # that is not 1-3 digits.
  class InvalidPrefixError < ArgumentError; end

  # Client is the jpzip SDK entry point. Construct it once and reuse it
  # across threads — it is safe for concurrent use.
  class Client
    # @param base_url [String] override the CDN origin
    # @param cache [Jpzip::Cache, nil] optional L2 persistent cache
    # @param memory_cache_size [Integer] L1 LRU capacity in prefix entries
    # @param on_spec_mismatch [Proc, nil] hook invoked once when /meta.json's
    #   spec_version differs from {Jpzip::SPEC_VERSION}
    # @param http_client [Proc, nil] testing hook receiving a URI, returning
    #   a Net::HTTPResponse-like object
    def initialize(base_url: DEFAULT_BASE_URL,
                   cache: nil,
                   memory_cache_size: MemoryLRU::DEFAULT_CAPACITY,
                   on_spec_mismatch: nil,
                   http_client: nil)
      @base_url = base_url.to_s.sub(%r{/+\z}, "")
      @cache = cache
      @mem = MemoryLRU.new(memory_cache_size)
      @on_spec_mismatch = on_spec_mismatch
      @http_client = http_client
      @meta_mu = Monitor.new
      @meta_cached = nil
      @meta_resolved = false
      @known_version = nil
    end

    # Lookup returns the ZipcodeEntry for +zipcode+ or nil if not found.
    # Malformed input returns nil without contacting the network.
    def lookup(zipcode)
      return nil unless ZIP_REGEX.match?(zipcode.to_s)

      dict = fetch_prefix_dict(zipcode[0, 3])
      return nil if dict.nil?

      dict[zipcode]
    end

    # LookupGroup fetches all entries under a 1-, 2-, or 3-digit prefix.
    # A 2-digit prefix fans out into 10 parallel prefix-3 fetches.
    #
    # @return [Hash{String => Jpzip::ZipcodeEntry}]
    def lookup_group(prefix)
      prefix = prefix.to_s
      raise InvalidPrefixError, "jpzip: prefix must be 1-3 digits, got #{prefix.inspect}" unless PREFIX_REGEX.match?(prefix)

      case prefix.length
      when 3
        fetch_prefix_dict(prefix) || {}
      when 1
        fetch_url(group_url(prefix)) || {}
      when 2
        parallel_merge(0.upto(9).map { |i| "#{prefix}#{i}" }) { |p3| fetch_prefix_dict(p3) }
      end
    end

    # LookupAll fans out across /g/0..9.json in parallel and merges. The CDN
    # does not publish a single /all.json because the combined file exceeds
    # Cloudflare Pages' 25 MiB per-file limit.
    def lookup_all
      parallel_merge(0.upto(9).map(&:to_s)) { |p1| fetch_url(group_url(p1)) }
    end

    # Meta returns the cached /meta.json. First call hits the network; later
    # calls return the cached value until {#refresh} is invoked.
    def meta
      @meta_mu.synchronize do
        return @meta_cached if @meta_resolved
      end

      result = Http.get("#{@base_url}/meta.json", http_client: @http_client)

      @meta_mu.synchronize do
        if result.status == 404
          @meta_resolved = true
          @meta_cached = nil
          return nil
        end

        parsed = JSON.parse(result.body)
        m = Meta.from_hash(parsed)

        if m.spec_version != SPEC_VERSION && @on_spec_mismatch
          @on_spec_mismatch.call(SPEC_VERSION, m.spec_version)
        end

        if @known_version && @known_version != m.version
          @mem.clear
          @cache&.clear
        end

        @known_version = m.version
        @meta_cached = m
        @meta_resolved = true
        m
      end
    end

    # Preload pulls the requested scope into L1 (and L2 when configured).
    # +scope+ is either the string "all" or a 1-3 digit prefix.
    def preload(scope)
      scope = scope.to_s
      if scope == "all"
        dict = lookup_all
        buckets = Hash.new { |h, k| h[k] = {} }
        dict.each { |zip, entry| buckets[zip[0, 3]][zip] = entry }
        buckets.each do |p, b|
          url = prefix_url(p)
          @mem.set(url, b)
          write_l2(url, b)
        end
        return nil
      end

      raise InvalidPrefixError, "jpzip: prefix must be 1-3 digits, got #{scope.inspect}" unless PREFIX_REGEX.match?(scope)

      lookup_group(scope)
      nil
    end

    # Refresh wipes L1 (and L2 when configured) and forgets cached meta.
    def refresh
      @mem.clear
      @meta_mu.synchronize do
        @meta_cached = nil
        @meta_resolved = false
        @known_version = nil
      end
      @cache&.clear
      nil
    end

    # @api private
    def memory_cache_size
      @mem.size
    end

    private

    def prefix_url(prefix3)
      "#{@base_url}/p/#{prefix3}.json"
    end

    def group_url(prefix1)
      "#{@base_url}/g/#{prefix1}.json"
    end

    def fetch_prefix_dict(prefix3)
      url = prefix_url(prefix3)
      if (cached = @mem.get(url))
        return cached
      end

      if (from_l2 = read_l2(url))
        @mem.set(url, from_l2)
        return from_l2
      end

      dict = fetch_url(url)
      if dict
        @mem.set(url, dict)
        write_l2(url, dict)
      end
      dict
    end

    def fetch_url(url)
      result = Http.get(url, http_client: @http_client)
      return nil if result.status == 404

      parsed = JSON.parse(result.body)
      parsed.each_with_object({}) do |(zip, raw), out|
        out[zip] = ZipcodeEntry.from_hash(raw)
      end
    end

    def read_l2(url)
      return nil unless @cache

      bytes = @cache.get(url)
      return nil if bytes.nil? || bytes.empty?

      begin
        parsed = JSON.parse(bytes)
      rescue JSON::ParserError
        @cache.delete(url)
        return nil
      end

      parsed.each_with_object({}) do |(zip, raw), out|
        out[zip] = ZipcodeEntry.from_hash(raw)
      end
    end

    def write_l2(url, dict)
      return unless @cache

      payload = dict.each_with_object({}) do |(zip, entry), h|
        h[zip] = entry.to_h
      end
      @cache.set(url, JSON.generate(payload))
    end

    # parallel_merge runs +block+ for each value in +items+ across up to 10
    # threads, then merges the resulting hashes (nils skipped). Raises the
    # first error if any thread fails.
    def parallel_merge(items)
      threads = items.map do |item|
        Thread.new do
          Thread.current.report_on_exception = false
          yield(item)
        end
      end

      results = threads.map(&:value)
      results.each_with_object({}) do |dict, out|
        next if dict.nil?

        out.merge!(dict)
      end
    end
  end
end

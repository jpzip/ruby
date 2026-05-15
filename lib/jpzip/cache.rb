# frozen_string_literal: true

require "monitor"

module Jpzip
  # Cache is the abstract interface a user-supplied L2 persistent cache must
  # satisfy. Implementations are free to add TTLs, eviction, or backends
  # (file, Redis, IndexedDB-equivalent, etc.).
  #
  # Subclasses MUST override every method below.
  class Cache
    # Get the bytes stored under +key+, or nil if absent.
    def get(key)
      raise NotImplementedError, "#{self.class}#get must be implemented"
    end

    # Set +value+ (a String of bytes) under +key+.
    def set(key, value)
      raise NotImplementedError, "#{self.class}#set must be implemented"
    end

    # Delete the entry stored under +key+ (no-op if absent).
    def delete(key)
      raise NotImplementedError, "#{self.class}#delete must be implemented"
    end

    # Clear every entry in the cache.
    def clear
      raise NotImplementedError, "#{self.class}#clear must be implemented"
    end
  end

  # MemoryLRU is the L1 in-memory cache, bounded by a fixed number of prefix
  # entries. It is safe for concurrent use.
  class MemoryLRU
    DEFAULT_CAPACITY = 100

    def initialize(capacity = DEFAULT_CAPACITY)
      @capacity = capacity < 1 ? 1 : capacity
      # Ruby's Hash preserves insertion order, so it doubles as an LRU index:
      # touch on read by deleting + re-inserting at the tail.
      @items = {}
      @mu = Monitor.new
    end

    def get(key)
      @mu.synchronize do
        return nil unless @items.key?(key)

        value = @items.delete(key)
        @items[key] = value
        value
      end
    end

    def set(key, value)
      @mu.synchronize do
        @items.delete(key) if @items.key?(key)
        @items[key] = value
        @items.shift while @items.size > @capacity
        nil
      end
    end

    def delete(key)
      @mu.synchronize { @items.delete(key) }
    end

    def clear
      @mu.synchronize { @items.clear }
      nil
    end

    def size
      @mu.synchronize { @items.size }
    end
  end
end

# frozen_string_literal: true

require_relative "test_helper"

class TestLookup < Minitest::Test
  def setup
    @base = TestFixtures::BASE
    @client = Jpzip::Client.new(base_url: @base)
  end

  def test_valid_zipcode
    assert Jpzip.valid_zipcode?("2310017")
    refute Jpzip.valid_zipcode?("231-0017")
    refute Jpzip.valid_zipcode?("12345")
    refute Jpzip.valid_zipcode?("abcdefg")
    refute Jpzip.valid_zipcode?(nil)
  end

  def test_lookup_returns_entry
    stub_request(:get, "#{@base}/p/231.json")
      .to_return(status: 200, body: { "2310017" => TestFixtures::ENTRY_2310017 }.to_json)

    entry = @client.lookup("2310017")
    refute_nil entry
    assert_equal "神奈川県", entry.prefecture
    assert_equal "横浜市中区", entry.city
    assert_equal "本町", entry.towns.first.town
    assert_nil entry.towns.first.note
  end

  def test_lookup_missing_zip_returns_nil
    stub_request(:get, "#{@base}/p/231.json")
      .to_return(status: 200, body: { "2310017" => TestFixtures::ENTRY_2310017 }.to_json)

    assert_nil @client.lookup("2319999")
  end

  def test_lookup_404_returns_nil
    stub_request(:get, "#{@base}/p/999.json").to_return(status: 404, body: "")
    assert_nil @client.lookup("9999999")
  end

  def test_lookup_invalid_zip_does_not_fetch
    # No stub on purpose — would raise WebMock error if called.
    assert_nil @client.lookup("231-0017")
    assert_nil @client.lookup("12345")
    assert_nil @client.lookup("")
  end

  def test_lookup_uses_l1_cache
    stub = stub_request(:get, "#{@base}/p/231.json")
           .to_return(status: 200, body: { "2310017" => TestFixtures::ENTRY_2310017 }.to_json)

    3.times { @client.lookup("2310017") }
    assert_requested stub, times: 1
  end

  def test_lookup_group_3_digit
    stub_request(:get, "#{@base}/p/231.json")
      .to_return(status: 200, body: { "2310017" => TestFixtures::ENTRY_2310017 }.to_json)

    dict = @client.lookup_group("231")
    assert_equal 1, dict.size
    assert_equal "神奈川県", dict["2310017"].prefecture
  end

  def test_lookup_group_2_digit_fans_out
    10.times do |i|
      stub_request(:get, "#{@base}/p/23#{i}.json")
        .to_return(status: 200, body: { "23#{i}0000" => TestFixtures::ENTRY_2310017 }.to_json)
    end

    dict = @client.lookup_group("23")
    assert_equal 10, dict.size
  end

  def test_lookup_group_1_digit
    stub_request(:get, "#{@base}/g/2.json")
      .to_return(status: 200, body: { "2310017" => TestFixtures::ENTRY_2310017 }.to_json)

    dict = @client.lookup_group("2")
    assert_equal 1, dict.size
  end

  def test_lookup_group_invalid_prefix
    assert_raises(Jpzip::InvalidPrefixError) { @client.lookup_group("abcd") }
    assert_raises(Jpzip::InvalidPrefixError) { @client.lookup_group("12345") }
  end

  def test_lookup_all_merges_all_groups
    10.times do |i|
      stub_request(:get, "#{@base}/g/#{i}.json")
        .to_return(status: 200, body: { "#{i}310831" => TestFixtures::ENTRY_2310017 }.to_json)
    end

    dict = @client.lookup_all
    assert_equal 10, dict.size
  end

  def test_meta_caches
    stub = stub_request(:get, "#{@base}/meta.json")
           .to_return(status: 200, body: TestFixtures.meta.to_json)

    m1 = @client.meta
    m2 = @client.meta
    assert_equal "2026-05", m1.version
    assert_same m1, m2
    assert_requested stub, times: 1
  end

  def test_meta_version_change_invalidates_cache
    # Seed L1 with a prefix entry.
    stub_request(:get, "#{@base}/p/231.json")
      .to_return(status: 200, body: { "2310017" => TestFixtures::ENTRY_2310017 }.to_json)
    @client.lookup("2310017")
    assert_equal 1, @client.memory_cache_size

    # First meta call records version.
    stub_request(:get, "#{@base}/meta.json")
      .to_return(
        { status: 200, body: TestFixtures.meta(version: "2026-05").to_json },
        { status: 200, body: TestFixtures.meta(version: "2026-06").to_json }
      )

    @client.meta
    assert_equal 1, @client.memory_cache_size

    # Force a second meta fetch by clearing the meta cache only — use refresh
    # would also clear L1 so simulate via a fresh fetch.
    @client.instance_variable_set(:@meta_resolved, false)
    @client.instance_variable_set(:@meta_cached, nil)

    @client.meta
    assert_equal 0, @client.memory_cache_size, "L1 should be invalidated on data version change"
  end

  def test_spec_mismatch_callback
    received = []
    client = Jpzip::Client.new(
      base_url: @base,
      on_spec_mismatch: ->(expected, got) { received << [expected, got] }
    )

    stub_request(:get, "#{@base}/meta.json")
      .to_return(status: 200, body: TestFixtures.meta(spec: "2.0").to_json)

    client.meta
    assert_equal [["1.0", "2.0"]], received
  end

  def test_refresh_clears_l1_and_meta
    stub_request(:get, "#{@base}/p/231.json")
      .to_return(status: 200, body: { "2310017" => TestFixtures::ENTRY_2310017 }.to_json)
    stub_request(:get, "#{@base}/meta.json")
      .to_return(status: 200, body: TestFixtures.meta.to_json)

    @client.lookup("2310017")
    @client.meta
    assert_equal 1, @client.memory_cache_size

    @client.refresh
    assert_equal 0, @client.memory_cache_size
    assert_nil @client.instance_variable_get(:@meta_cached)
  end

  def test_retry_on_500
    stub = stub_request(:get, "#{@base}/p/231.json")
           .to_return({ status: 500, body: "boom" },
                      { status: 500, body: "boom" },
                      { status: 200, body: { "2310017" => TestFixtures::ENTRY_2310017 }.to_json })

    # Disable backoff to keep the test fast.
    Jpzip::Http.stub(:sleep, ->(_d) {}) do
      entry = @client.lookup("2310017")
      refute_nil entry
    end
    assert_requested stub, times: 3
  end

  def test_no_retry_on_4xx
    # Regression: a non-404 4xx must propagate immediately. If retry logic
    # ever treated it as transient the request count would jump to 3.
    stub = stub_request(:get, "#{@base}/p/231.json")
           .to_return(status: 403, body: "forbidden")

    assert_raises(Jpzip::Http::HttpError) { @client.lookup("2310017") }
    assert_requested stub, times: 1
  end

  def test_l2_cache_round_trip
    cache = build_memory_l2_cache
    client = Jpzip::Client.new(base_url: @base, cache: cache)

    stub_request(:get, "#{@base}/p/231.json")
      .to_return(status: 200, body: { "2310017" => TestFixtures::ENTRY_2310017 }.to_json)

    client.lookup("2310017")
    # Build a new client that shares the same L2 — no network needed.
    client2 = Jpzip::Client.new(base_url: @base, cache: cache)
    entry = client2.lookup("2310017")
    refute_nil entry
    assert_equal "神奈川県", entry.prefecture
  end

  def test_data_define_immutable
    entry = Jpzip::ZipcodeEntry.from_hash(TestFixtures::ENTRY_2310017)
    assert_kind_of Jpzip::ZipcodeEntry, entry
    assert_raises(NoMethodError) { entry.prefecture = "x" }
  end

  private

  def build_memory_l2_cache
    Class.new(Jpzip::Cache) do
      def initialize
        super
        @store = {}
      end

      def get(key); @store[key]; end
      def set(key, value); @store[key] = value; end
      def delete(key); @store.delete(key); end
      def clear; @store.clear; end
    end.new
  end
end

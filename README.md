# jpzip

[![Gem Version](https://img.shields.io/gem/v/jpzip.svg)](https://rubygems.org/gems/jpzip)
[![Gem Downloads](https://img.shields.io/gem/dt/jpzip.svg)](https://rubygems.org/gems/jpzip)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Publish](https://github.com/jpzip/ruby/actions/workflows/publish.yml/badge.svg)](https://github.com/jpzip/ruby/actions/workflows/publish.yml)

> Ruby SDK for **jpzip** — a free, unlimited Japanese postal code (郵便番号) API.
> 日本の全郵便番号 120,677 件を CDN 配信 JSON から引く Ruby gem。

**English** | [日本語](./README.ja.md)

`jpzip` looks up Japanese postal codes (郵便番号) from `jpzip.nadai.dev`,
a CDN-hosted dataset built from Japan Post's `KEN_ALL.csv` and `KEN_ALL_ROME.csv`
normalized to JSON. No registration, no rate limits, no API key.

- 🇯🇵 **Complete dataset** — 120,677 entries with kanji, kana, romaji, and government codes (JIS X 0401 / 総務省地方公共団体コード)
- ⚡️ **Fast** — L1 LRU + optional L2 persistent cache; `preload` to serve lookups without per-request network round-trips
- 🛡️ **Resilient** — 3-attempt retry with exponential backoff on 5xx / network failures
- 🪶 **Zero runtime deps** — `net/http` + `json` + `monitor`, all stdlib
- 🆓 **Free forever** — backed by Cloudflare Pages' free tier (no billing axis exists)
- 🔌 **Drop-in** — same API surface across [every jpzip SDK](#other-languages)

## Requirements

Ruby 3.2+ (uses `Data.define`)

## Install

```ruby
# Gemfile
gem "jpzip"
```

Or directly:

```sh
gem install jpzip
```

## Quick Start

```ruby
require "jpzip"

entry = Jpzip.lookup("2310017")
# entry is nil when not found
puts "#{entry.prefecture} #{entry.city} #{entry.towns.first.town}"
# => 神奈川県 横浜市中区 港町
```

Romaji and government codes are included on the same entry:

```ruby
puts "#{entry.prefecture_roma} #{entry.city_roma} #{entry.towns.first.roma}"
# => Kanagawa Ken Yokohama Shi Naka Ku Minatocho

puts "#{entry.prefecture_code} #{entry.city_code}"
# => 14 14104
```

Entries are immutable `Data.define` values:

```ruby
entry.prefecture = "x"  # raises NoMethodError
```

## Use Cases

### Zipcode lookup HTTP endpoint (Rails)

```ruby
# config/routes.rb
get "/api/zipcode/:code", to: "zipcodes#show"

# app/controllers/zipcodes_controller.rb
class ZipcodesController < ApplicationController
  def show
    entry = Jpzip.lookup(params[:code])
    return head :not_found if entry.nil?

    render json: {
      prefecture: entry.prefecture,
      city:       entry.city,
      town:       entry.towns.first&.town,
      codes:      { prefecture: entry.prefecture_code, city: entry.city_code }
    }
  end
end
```

### Zipcode lookup HTTP endpoint (Sinatra)

```ruby
require "sinatra"
require "jpzip"
require "json"

get "/api/zipcode/:code" do
  entry = Jpzip.lookup(params[:code])
  halt 404 if entry.nil?

  content_type :json
  {
    prefecture: entry.prefecture,
    city:       entry.city,
    town:       entry.towns.first&.town
  }.to_json
end
```

### Batch validation

```ruby
all = Jpzip.lookup_all # entire dataset in memory (~37 MiB JSON)
csv_zipcodes.each do |zip|
  warn "invalid zipcode: #{zip}" unless all.key?(zip)
end
```

### Serve lookups from cache (BYO L2 backend)

The dataset is partitioned into 948 three-digit prefix buckets. The default
L1 (100 entries) keeps the hottest buckets; to cache the whole dataset, pair
`preload("all")` with an L2 cache or raise `memory_cache_size` above 948.

```ruby
client = Jpzip::Client.new(
  memory_cache_size: 1024,
  cache: my_file_cache # any Jpzip::Cache subclass
)
client.preload("all")
# Subsequent lookups are served from L1/L2 without hitting the network.
entry = client.lookup("2310017")
```

## API Reference

### Module functions (share a process-wide default Client)

| Function | Description |
|---|---|
| `Jpzip.lookup(zipcode)` | Look up a single 7-digit zipcode. Returns `nil` if not found or malformed (no network call for malformed input). |
| `Jpzip.lookup_group(prefix)` | Look up by 1-, 2-, or 3-digit prefix. 1-digit fetches `/g/{d}.json`; 3-digit fetches `/p/{ddd}.json`; 2-digit fans out into 10 parallel 3-digit fetches and merges. |
| `Jpzip.lookup_all` | Fetch entire dataset (120k entries, ~37 MiB) in parallel across `/g/0..9.json`. |
| `Jpzip.meta` | Dataset version, generated-at, per-prefecture counts, spec version. Result is cached until the default client is reset. |
| `Jpzip.preload(scope)` | Warm L1 (and L2 when configured) for `"all"` or a specific prefix. |
| `Jpzip.valid_zipcode?(str)` | Pure syntax check (`\A\d{7}\z`) — no network. |
| `Jpzip.configure(**opts)` | Replace the singleton with a configured `Client` (e.g. to share an L2 cache through the module helpers). |
| `Jpzip.reset_default_client!` | Drop the singleton (mainly for tests). |

### `Jpzip::Client` (advanced)

`Client.new` returns a configurable instance; required for L2 caching, custom HTTP behavior, alternate base URL, or multiple isolated caches. Instances are thread-safe.

```ruby
client = Jpzip::Client.new(
  base_url:          "https://jpzip.nadai.dev",
  memory_cache_size: 200, # L1 capacity in prefix buckets, default 100
  cache:             my_cache, # optional L2 (Jpzip::Cache subclass)
  on_spec_mismatch:  ->(expected, got) {
    warn "jpzip spec mismatch: SDK=#{expected} server=#{got}"
  }
)
```

`Client` exposes `#lookup` / `#lookup_group` / `#lookup_all` / `#meta` / `#preload` plus:

| Method | Description |
|---|---|
| `client.refresh` | Wipe L1 (and L2 when configured) and forget cached meta. |

When `meta` observes that `/meta.json`'s `version` has changed since the last successful fetch, L1 and L2 are cleared automatically — call `meta` periodically to pick up dataset rollovers.

### Errors

- `Jpzip::InvalidPrefixError < ArgumentError` — raised by `lookup_group` / `preload` when the prefix is not 1-3 digits.
- `Jpzip::Http::HttpError < StandardError` — raised on 4xx (other than 404, which yields `nil`) or after exhausted retries on 5xx.
- Transient network failures and 5xx responses are retried up to 3 attempts (initial + 2 retries) with exponential backoff sleeps of 400ms and 800ms.

### `Jpzip::Cache` interface

Bring your own L2 backend (file, Redis, Memcached, etc.) by subclassing `Jpzip::Cache`:

```ruby
class MyFileCache < Jpzip::Cache
  def get(key)            # => String (raw JSON bytes) or nil
    # ...
  end

  def set(key, value)     # value is a String of bytes
    # ...
  end

  def delete(key)
    # ...
  end

  def clear
    # ...
  end
end
```

Keys are the full prefix-bucket URLs (e.g. `https://jpzip.nadai.dev/p/231.json`); values are raw JSON bytes.

### Data types

`Jpzip::ZipcodeEntry` and `Jpzip::Town` are immutable `Data.define` classes with `from_hash` / `to_h` helpers. Fields: `prefecture`, `prefecture_kana`, `prefecture_roma`, `prefecture_code`, `city`, `city_kana`, `city_roma`, `city_code`, `towns` (Array of `Town`). `Town` has `town`, `kana`, `roma`, `note`.

## Why jpzip?

| | **jpzip** | [jpostcode][jpostcode] | [ken_all][kenall] | [zipcloud API][zipcloud] |
|---|---|---|---|---|
| Romaji (`Yokohama Shi`) | ✅ | ❌ | ❌ | ❌ |
| Government codes (JIS / 総務省) | ✅ | ⚠️ Prefecture only | ⚠️ JIS only | ❌ |
| No manual CSV / submodule sync | ✅ | ❌ Git submodule | ❌ Rake task | ✅ |
| Monthly updates | ✅ Auto | ⚠️ Manual submodule | ❌ Manual | ✅ |
| Offline after preload | ✅ | ✅ Local data | ✅ Local DB | ❌ |
| Rate-limit-free | ✅ | ✅ | ✅ | ⚠️ Discouraged |
| L1 + pluggable L2 cache | ✅ | ❌ | ❌ | ❌ |
| Zero runtime dependencies | ✅ | ⚠️ jpostcode-data submodule | ❌ Rails / activerecord-import / rubyzip / curses | n/a |

[jpostcode]: https://github.com/kufu/jpostcode-rb
[kenall]: https://github.com/ozin/ken_all
[zipcloud]: http://zipcloud.ibsnet.co.jp/doc/api

## Other Languages

Same API surface across all SDKs:

[Go](https://github.com/jpzip/go) · [TypeScript](https://github.com/jpzip/js) · [Python](https://github.com/jpzip/python) · [Rust](https://github.com/jpzip/rust) · [PHP](https://github.com/jpzip/php) · [Swift](https://github.com/jpzip/swift) · [Dart](https://github.com/jpzip/dart)

## Resources

- **Website** — https://jpzip.nadai.dev
- **Protocol spec** — [jpzip/spec](https://github.com/jpzip/spec)
- **Data ETL** — [jpzip/data](https://github.com/jpzip/data)
- **MCP server** — [jpzip/mcp](https://github.com/jpzip/mcp) — use jpzip from Claude / ChatGPT / Cursor

## Keywords

japanese postal code, japan zipcode, 郵便番号, KEN_ALL, KEN_ALL_ROME, address validation, japan address api, postal code lookup ruby, ruby japanese address gem, JIS X 0401, 総務省地方公共団体コード, rails postal code

## License

[MIT](./LICENSE)

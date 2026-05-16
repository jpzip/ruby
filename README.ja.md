# jpzip

[![Gem Version](https://img.shields.io/gem/v/jpzip.svg)](https://rubygems.org/gems/jpzip)
[![Gem Downloads](https://img.shields.io/gem/dt/jpzip.svg)](https://rubygems.org/gems/jpzip)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Publish](https://github.com/jpzip/ruby/actions/workflows/publish.yml/badge.svg)](https://github.com/jpzip/ruby/actions/workflows/publish.yml)

> **jpzip** の Ruby SDK — 無料・無制限の日本郵便番号 API。
> 日本郵便の `KEN_ALL.csv` / `KEN_ALL_ROME.csv` を JSON 正規化し CDN 配信。

[English](./README.md) | **日本語**

`jpzip` は `jpzip.nadai.dev` から日本の郵便番号 120,677 件を引く Ruby gem です。
登録不要、レート制限なし、API キー不要。

- 🇯🇵 **全件収録** — 漢字・カナ・ローマ字・自治体コード(JIS X 0401 / 総務省地方公共団体コード)
- ⚡️ **高速** — L1 LRU + 任意の L2 永続キャッシュ。`preload` でネットワーク往復なしのルックアップが可能
- 🛡️ **堅牢** — 5xx / ネットワーク失敗時は指数バックオフで最大 3 回リトライ
- 🪶 **依存ゼロ** — `net/http` / `json` / `monitor` の標準ライブラリのみ
- 🆓 **永久無料** — Cloudflare Pages 無料枠で運用(課金軸が存在しない)
- 🔌 **同一 API** — [全 jpzip SDK](#他言語版) で API が揃う

## 必要環境

Ruby 3.2+(`Data.define` を使用)

## インストール

```ruby
# Gemfile
gem "jpzip"
```

または直接:

```sh
gem install jpzip
```

## クイックスタート

```ruby
require "jpzip"

entry = Jpzip.lookup("2310017")
# 見つからない場合 entry は nil
puts "#{entry.prefecture} #{entry.city} #{entry.towns.first.town}"
# => 神奈川県 横浜市中区 港町
```

ローマ字・自治体コードも同じエントリに含まれます:

```ruby
puts "#{entry.prefecture_roma} #{entry.city_roma} #{entry.towns.first.roma}"
# => Kanagawa Ken Yokohama Shi Naka Ku Minatocho

puts "#{entry.prefecture_code} #{entry.city_code}"
# => 14 14104
```

エントリはイミュータブルな `Data.define` 値です:

```ruby
entry.prefecture = "x"  # NoMethodError
```

## ユースケース

### 郵便番号ルックアップ HTTP エンドポイント(Rails)

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

### 郵便番号ルックアップ HTTP エンドポイント(Sinatra)

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

### CSV のバッチ検証

```ruby
all = Jpzip.lookup_all # 全件をメモリに展開(JSON 約 37 MiB)
csv_zipcodes.each do |zip|
  warn "不正な郵便番号: #{zip}" unless all.key?(zip)
end
```

### キャッシュからの提供(任意の L2 バックエンド)

データは 948 個の 3 桁 prefix バケットに分割されています。デフォルト L1(100 件)
はホットなバケットを保持しますが、全件を常駐させるには L2 を併用するか
`memory_cache_size` を 948 超に設定してください。

```ruby
client = Jpzip::Client.new(
  memory_cache_size: 1024,
  cache: my_file_cache # Jpzip::Cache サブクラス
)
client.preload("all")
# 以降の lookup は L1/L2 で完結し、ネットワークにアクセスしない
entry = client.lookup("2310017")
```

## API リファレンス

### モジュール関数(プロセス内 default Client を共有)

| 関数 | 説明 |
|---|---|
| `Jpzip.lookup(zipcode)` | 7 桁の郵便番号で 1 件引く。見つからない / 不正な入力は `nil`(不正入力時はネットワーク不使用)。 |
| `Jpzip.lookup_group(prefix)` | 1〜3 桁の prefix で引く。1 桁は `/g/{d}.json` を 1 回、3 桁は `/p/{ddd}.json` を 1 回、2 桁は 10 並列 fetch して結合。 |
| `Jpzip.lookup_all` | `/g/0..9.json` を並列取得して全件(120k 件、約 37 MiB)を返す。 |
| `Jpzip.meta` | データバージョン・生成日時・都道府県別件数・spec version。default client がリセットされるまで結果をキャッシュ。 |
| `Jpzip.preload(scope)` | `"all"` または特定 prefix で L1(L2 設定時は L2 も)を温める。 |
| `Jpzip.valid_zipcode?(str)` | 純粋な書式チェック(`\A\d{7}\z`)。ネットワーク不使用。 |
| `Jpzip.configure(**opts)` | 設定済み `Client` でシングルトンを差し替え(モジュール関数経由で L2 を共有したい場合等)。 |
| `Jpzip.reset_default_client!` | シングルトン破棄(主にテスト用)。 |

### `Jpzip::Client`(高度な用途)

`Client.new` で設定可能なインスタンスを取得。L2 キャッシュ、HTTP 挙動の差し替え、配信元変更、複数の独立キャッシュが必要な場合に使用。インスタンスはスレッドセーフ。

```ruby
client = Jpzip::Client.new(
  base_url:          "https://jpzip.nadai.dev",
  memory_cache_size: 200, # L1 容量(prefix バケット数)、デフォルト 100
  cache:             my_cache, # L2(任意、Jpzip::Cache サブクラス)
  on_spec_mismatch:  ->(expected, got) {
    warn "jpzip spec 不一致: SDK=#{expected} server=#{got}"
  }
)
```

`Client` は `#lookup` / `#lookup_group` / `#lookup_all` / `#meta` / `#preload` に加えて:

| メソッド | 説明 |
|---|---|
| `client.refresh` | L1(L2 設定時は L2 も)を消し、キャッシュ済み meta を破棄。 |

`meta` が `/meta.json` の `version` 変更を検知すると L1/L2 が自動クリアされます。データ切り替えに追従するには `meta` を定期的に呼んでください。

### エラー

- `Jpzip::InvalidPrefixError < ArgumentError` — prefix が 1〜3 桁でない場合に `lookup_group` / `preload` から送出。
- `Jpzip::Http::HttpError < StandardError` — 404 以外の 4xx、または 5xx のリトライ枯渇時に送出(404 は `nil`)。
- ネットワーク失敗と 5xx は最大 3 回試行(初回 + リトライ 2 回)、指数バックオフのスリープは 400ms / 800ms。

### `Jpzip::Cache` インターフェース

任意の L2 バックエンド(ファイル / Redis / Memcached など)を `Jpzip::Cache` のサブクラスとして渡せます:

```ruby
class MyFileCache < Jpzip::Cache
  def get(key)            # => String(生 JSON バイト列)または nil
    # ...
  end

  def set(key, value)     # value は String
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

キーは prefix バケットの完全 URL(例: `https://jpzip.nadai.dev/p/231.json`)、値は生 JSON バイト列。

### データ型

`Jpzip::ZipcodeEntry` と `Jpzip::Town` はイミュータブルな `Data.define` クラス。`from_hash` / `to_h` ヘルパーを持ちます。フィールド: `prefecture`, `prefecture_kana`, `prefecture_roma`, `prefecture_code`, `city`, `city_kana`, `city_roma`, `city_code`, `towns`(`Town` の配列)。`Town` は `town`, `kana`, `roma`, `note`。

## なぜ jpzip か

| | **jpzip** | [jpostcode][jpostcode] | [ken_all][kenall] | [zipcloud API][zipcloud] |
|---|---|---|---|---|
| ローマ字(`Yokohama Shi`) | ✅ | ❌ | ❌ | ❌ |
| 自治体コード(JIS / 総務省) | ✅ | ⚠️ 都道府県のみ | ⚠️ JIS のみ | ❌ |
| CSV / submodule 手動同期不要 | ✅ | ❌ git submodule | ❌ rake task | ✅ |
| 月次更新 | ✅ 自動 | ⚠️ submodule 手動 | ❌ 手動 | ✅ |
| Preload 後オフライン | ✅ | ✅ ローカルデータ | ✅ ローカル DB | ❌ |
| レート制限なし | ✅ | ✅ | ✅ | ⚠️ 大量アクセス非推奨 |
| L1 + 差し替え可能な L2 | ✅ | ❌ | ❌ | ❌ |
| 実行時依存ゼロ | ✅ | ⚠️ jpostcode-data submodule | ❌ Rails / activerecord-import / rubyzip / curses | n/a |

[jpostcode]: https://github.com/kufu/jpostcode-rb
[kenall]: https://github.com/ozin/ken_all
[zipcloud]: http://zipcloud.ibsnet.co.jp/doc/api

## 他言語版

全 SDK で同一の API を提供しています:

[Go](https://github.com/jpzip/go) · [TypeScript](https://github.com/jpzip/js) · [Python](https://github.com/jpzip/python) · [Rust](https://github.com/jpzip/rust) · [PHP](https://github.com/jpzip/php) · [Swift](https://github.com/jpzip/swift) · [Dart](https://github.com/jpzip/dart)

## 関連リソース

- **Web サイト** — https://jpzip.nadai.dev
- **プロトコル仕様** — [jpzip/spec](https://github.com/jpzip/spec)
- **データ ETL** — [jpzip/data](https://github.com/jpzip/data)
- **MCP サーバー** — [jpzip/mcp](https://github.com/jpzip/mcp) — Claude / ChatGPT / Cursor から jpzip を呼ぶ

## キーワード

日本郵便番号, 郵便番号, KEN_ALL, KEN_ALL_ROME, 住所検索, 住所バリデーション, japanese postal code, japan zipcode, ruby japanese address gem, Rails 郵便番号, JIS X 0401, 総務省地方公共団体コード

## ライセンス

[MIT](./LICENSE)

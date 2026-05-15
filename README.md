# jpzip — Ruby SDK

> 日本の郵便番号を CDN 配信の JSON データから引く Ruby SDK。

- 配信ドメイン: `https://jpzip.nadai.dev`
- プロトコル仕様: [`jpzip/spec`](https://github.com/jpzip/spec)
- データ ETL: [`jpzip/data`](https://github.com/jpzip/data)

```ruby
# Gemfile
gem "jpzip"
```

または直接:

```sh
gem install jpzip
```

Ruby 3.2 以上が必要(`Data.define` を使用)。

## 使い方

### モジュール関数 API

```ruby
require "jpzip"

entry = Jpzip.lookup("2310831")
# entry == nil なら見つからなかった
# entry.prefecture          #=> "神奈川県"
# entry.city                #=> "横浜市中区"
# entry.towns.first.town    #=> "矢口台"

dict = Jpzip.lookup_group("23")  # 2 桁は 10 並列 fetch
all  = Jpzip.lookup_all
meta = Jpzip.meta

Jpzip.valid_zipcode?("2310831")  #=> true
Jpzip.valid_zipcode?("231-0831") #=> false
```

### クライアント API (L2 キャッシュ・複数インスタンス用)

```ruby
client = Jpzip::Client.new(
  base_url: "https://jpzip.nadai.dev",
  memory_cache_size: 200,
  cache: my_cache,                       # Jpzip::Cache サブクラス
  on_spec_mismatch: ->(expected, got) {
    warn "jpzip spec mismatch: expected=#{expected} got=#{got}"
  }
)

client.preload("all")
entry = client.lookup("2310831")
```

## Cache インターフェース

```ruby
class MyFileCache < Jpzip::Cache
  def get(key);           ...; end  # => String or nil
  def set(key, value);    ...; end
  def delete(key);        ...; end
  def clear;              ...; end
end
```

ファイル / Redis / Memcached 等の任意の実装を渡せる。L2 は明示的に有効化した場合のみ使われ、デフォルトは L1 (メモリ LRU) のみ。

## 入力検証

`Jpzip.lookup` は `\A\d{7}\z` にマッチしない入力に対して fetch せず `nil` を返す。

## バージョン整合性

`Jpzip.meta` 取得時、`spec_version` が SDK 対応バージョンと異なる場合 `on_spec_mismatch` コールバックが 1 度だけ呼ばれる。データバージョンが変わったら L1/L2 を自動 invalidate する。

## 並列性とスレッドセーフ

`Jpzip::Client` はスレッドセーフ。複数スレッドから同一インスタンスを共有しても安全。`lookup_group("23")` や `lookup_all` は内部で `Thread` を使って並列 fetch する。

## 依存

なし。Ruby 標準ライブラリ (`net/http`, `json`, `monitor`) のみ使用。

## ライセンス

[MIT](./LICENSE)

# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

require "minitest/autorun"
require "webmock/minitest"
require "json"

require "jpzip"

WebMock.disable_net_connect!(allow_localhost: true)

module TestFixtures
  BASE = "https://jpzip.example"

  ENTRY_2310017 = {
    "prefecture" => "神奈川県",
    "prefecture_kana" => "カナガワケン",
    "prefecture_roma" => "Kanagawa",
    "prefecture_code" => "14",
    "city" => "横浜市中区",
    "city_kana" => "ヨコハマシナカク",
    "city_roma" => "Yokohama Shi Naka Ku",
    "city_code" => "14104",
    "towns" => [
      { "town" => "本町", "kana" => "ホンチョウ", "roma" => "Honcho" }
    ]
  }.freeze

  ENTRY_4980000 = {
    "prefecture" => "三重県",
    "prefecture_kana" => "ミエケン",
    "prefecture_roma" => "Mie",
    "prefecture_code" => "24",
    "city" => "桑名市",
    "city_kana" => "クワナシ",
    "city_roma" => "Kuwana Shi",
    "city_code" => "24205",
    "towns" => [
      { "town" => "", "kana" => "", "roma" => "", "note" => "以下に掲載がない場合" }
    ]
  }.freeze

  def self.meta(version: "2026-05", spec: "1.0")
    {
      "version" => version,
      "generated_at" => "2026-05-01T00:00:00Z",
      "spec_version" => spec,
      "total_zipcodes" => 1,
      "prefix_count" => 1,
      "by_pref" => { "14" => 1 },
      "data_source" => "https://example.test",
      "endpoints" => { "group" => "/g/{prefix1}.json", "prefix" => "/p/{prefix3}.json" }
    }
  end
end

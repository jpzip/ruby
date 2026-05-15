# frozen_string_literal: true

module Jpzip
  # Town corresponds to one element of ZipcodeEntry#towns.
  #
  # Fields match the JSON shape served by the CDN (snake_case).
  Town = Data.define(:town, :kana, :roma, :note) do
    # Build a Town from a parsed JSON hash. Unknown keys are ignored so the
    # SDK keeps working when the protocol grows new optional fields.
    def self.from_hash(h)
      new(
        town: h["town"] || "",
        kana: h["kana"] || "",
        roma: h["roma"] || "",
        note: h["note"]
      )
    end

    def to_h
      base = { town: town, kana: kana, roma: roma }
      base[:note] = note if note
      base
    end
  end

  # ZipcodeEntry is one logical entry as published by the CDN.
  ZipcodeEntry = Data.define(
    :prefecture,
    :prefecture_kana,
    :prefecture_roma,
    :prefecture_code,
    :city,
    :city_kana,
    :city_roma,
    :city_code,
    :towns
  ) do
    def self.from_hash(h)
      new(
        prefecture: h["prefecture"] || "",
        prefecture_kana: h["prefecture_kana"] || "",
        prefecture_roma: h["prefecture_roma"] || "",
        prefecture_code: h["prefecture_code"] || "",
        city: h["city"] || "",
        city_kana: h["city_kana"] || "",
        city_roma: h["city_roma"] || "",
        city_code: h["city_code"] || "",
        towns: (h["towns"] || []).map { |t| Town.from_hash(t) }
      )
    end
  end

  # Endpoints is part of /meta.json.
  Endpoints = Data.define(:group, :prefix) do
    def self.from_hash(h)
      new(group: h["group"] || "", prefix: h["prefix"] || "")
    end
  end

  # Meta is /meta.json.
  Meta = Data.define(
    :version,
    :generated_at,
    :spec_version,
    :total_zipcodes,
    :prefix_count,
    :by_pref,
    :data_source,
    :endpoints
  ) do
    def self.from_hash(h)
      new(
        version: h["version"] || "",
        generated_at: h["generated_at"] || "",
        spec_version: h["spec_version"] || "",
        total_zipcodes: h["total_zipcodes"] || 0,
        prefix_count: h["prefix_count"] || 0,
        by_pref: h["by_pref"] || {},
        data_source: h["data_source"] || "",
        endpoints: Endpoints.from_hash(h["endpoints"] || {})
      )
    end
  end
end

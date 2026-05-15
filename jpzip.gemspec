# frozen_string_literal: true

require_relative "lib/jpzip/version"

Gem::Specification.new do |spec|
  spec.name          = "jpzip"
  spec.version       = Jpzip::VERSION
  spec.authors       = ["nadai"]
  spec.email         = ["noreply@nadai.dev"]

  spec.summary       = "Ruby SDK for the jpzip Japanese postal-code dataset"
  spec.description   = "jpzip は日本の郵便番号を CDN 配信の JSON データから引く Ruby SDK。" \
                       "L1 LRU メモリキャッシュを内蔵し、任意の L2 永続キャッシュを差し込める。"
  spec.homepage      = "https://github.com/jpzip/ruby"
  spec.license       = "MIT"
  spec.required_ruby_version = ">= 3.2"

  spec.metadata = {
    "homepage_uri"      => spec.homepage,
    "source_code_uri"   => "https://github.com/jpzip/ruby",
    "bug_tracker_uri"   => "https://github.com/jpzip/ruby/issues",
    "documentation_uri" => "https://github.com/jpzip/ruby",
    "rubygems_mfa_required" => "true"
  }

  spec.files = Dir[
    "lib/**/*.rb",
    "README.md",
    "LICENSE",
    "jpzip.gemspec"
  ]
  spec.require_paths = ["lib"]

  # No runtime dependencies — net/http and json ship with Ruby.

  spec.add_development_dependency "minitest", "~> 5.20"
  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "webmock", "~> 3.20"
end

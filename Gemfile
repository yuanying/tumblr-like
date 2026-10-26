source "https://rubygems.org"

gem "oauth"
# 0.8.6 exists only as a tag on GitHub. The last release on rubygems.org, 0.8.5,
# pins faraday ~> 0.9, which no longer loads on Ruby 3 and later.
gem "tumblr_client", github: "tumblr/tumblr_client", tag: "v0.8.6"
# The JSON middleware of faraday 1.x, which tumblr_client 0.8.6 pins, calls
# JSON.parse with arguments json 3 no longer takes.
gem "json", "~> 2.0"
gem "nokogiri"

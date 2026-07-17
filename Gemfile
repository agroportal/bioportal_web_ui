source 'https://rubygems.org'

# Main Rails gem
# Bundle edge Rails instead: gem 'rails', github: 'rails/rails'
gem 'rails', '7.0.8'

# JavaScript bundling for Rails
gem 'jsbundling-rails'

# Chart.js integration for Rails
gem 'chart-js-rails'

# SassC as a replacement for sass-rails
gem 'sassc-rails' # sass-rails replacement

# Terser JavaScript minifier as a replacement for Uglifier
gem 'terser' # uglifier replacement

# Bootstrap front-end framework
gem 'bootstrap', '~> 4.2.0'

# jQuery integration for Rails
gem 'jquery-rails'

# jQuery UI integration for Rails
gem 'jquery-ui-rails'

# The original asset pipeline for Rails
# [https://github.com/rails/sprockets-rails]
gem 'sprockets-rails'

# Use the Puma web server
# [https://github.com/puma/puma]
gem 'puma', '~> 5.0'

# Use JavaScript with ESM import maps
# [https://github.com/rails/importmap-rails]
gem 'importmap-rails'

# Hotwire's SPA-like page accelerator
# [https://turbo.hotwired.dev]
gem 'turbo-rails'

# Hotwire's modest JavaScript framework
# [https://stimulus.hotwired.dev]
gem 'stimulus-rails'

# Debugging tool
# See https://guides.rubyonrails.org/debugging_rails_applications.html#debugging-with-the-debug-gem  gem 'pry'
gem 'pry'

# Time zone info for Windows platforms
gem 'tzinfo-data', platforms: %i[mingw mswin x64_mingw jruby]

# Reduces boot times through caching; required in config/boot.rb
gem 'bootsnap', require: false

# Memcached client for Ruby
gem 'dalli'

# GraphQL client for Ruby
gem 'graphql-client'

# Haml template engine for Ruby on Rails
gem 'haml', '~> 5.1'

# Internationalization (i18n)
gem 'i18n'
gem 'rails-i18n', '~> 7.0.0'

# MySQL database adapter
gem 'mysql2'

# JSON parsing libraries
gem 'multi_json'
gem 'oj'

# Google reCAPTCHA integration
gem 'recaptcha', '~> 5.9.0'

# Simple HTTP and REST client for Ruby
gem 'rest-client'

# View components framework for Rails
gem 'lookbook', '~> 1.5.5'
gem 'view_component', '~> 2.72'

# Pagination library for Rails
gem 'will_paginate', '~> 3.0'

# String similarity, used by federated search to rank results
gem 'string-similarity'

# Render SVG files in Rails views
gem 'inline_svg'

# ISO language codes and flags
gem 'flag-icons-rails', '~> 3.4'
gem 'iso-639', '~> 0.3.6'
gem 'countries', '~> 5.7'

# Custom API client
gem 'ontologies_api_client', git: 'https://github.com/agroportal/ontologies_api_ruby_client.git', branch: 'development'

# SSRF protection for the URI resolvability checker
gem 'ssrf_filter', '~> 1.5'

# Ruby 2.7.8 pinned gems (to remove when migrating to Ruby >= 3.0)

gem 'ffi', '~> 1.16.3'
gem 'net-ftp', '~> 0.2.0', require: false
gem 'net-http', '~> 0.3.2'

# Multi-Provider Authentication
gem 'omniauth'
gem 'omniauth-rails_csrf_protection'
gem 'omniauth-github'
gem 'omniauth-google-oauth2'
gem 'omniauth-keycloak'
gem 'omniauth-orcid'

# Used to generate colors randomly
gem "color", "~> 1.8"

group :staging, :production, :appliance do
  # Monitoring and performance profiling
  gem "stackprof", "~> 0.2.27"
  gem "sentry-ruby", "~> 5.23"
  gem "sentry-rails", "~> 5.23"
  # Logs in JSON format, useful for shipping logs to logstash
  # gem 'rackstash', git: 'https://github.com/planio-gmbh/rackstash.git'
  # gem 'logstash-logger'
end

group :development do
  # Capistrano Deployment
  gem 'bcrypt_pbkdf', '>= 1.0', '< 2.0', require: false # https://github.com/miloserdow/capistrano-deploy/issues/42
  gem 'capistrano', '~> 3.11', require: false
  gem 'capistrano-bundler', require: false
  gem 'capistrano-locally', require: false
  gem 'capistrano-passenger', require: false
  gem 'capistrano-rails', '~> 1.4', require: false
  gem 'capistrano-yarn', require: false
  gem 'ed25519', '>= 1.2', '< 2.0', require: false # https://github.com/miloserdow/capistrano-deploy/issues/42

  # Static code analysis
  gem 'brakeman', require: false
  gem 'rubocop', require: false

  # Haml support for Rails
  gem 'haml-rails'
  gem 'html2haml'

  # Debugging tools
  gem 'debug', platforms: %i[mri mingw x64_mingw]

  # Use console on exceptions pages
  # [https://github.com/rails/web-console]
  gem 'web-console'

  # Internationalization tasks
  # gem 'i18n-debug'
  gem 'i18n-tasks'
  gem 'i18n-tasks-csv', '~> 1.1'
  gem 'deepl-rb'

  # Email preview in the browser
  gem 'letter_opener_web', '~> 2.0'
end

group :test do
  # System testing
  # [https://guides.rubyonrails.org/testing.html#system-testing]
  gem 'capybara'

  # WebDriver for system testing
  gem 'selenium-webdriver'

  # Code coverage generation
  gem 'simplecov', require: false
  gem 'simplecov-cobertura' # for codecov.io

  # Mock HTTP requests in tests
  gem 'webmock'

  # Testing framework for Rails
  gem 'rspec-rails'
end

gem 'concurrent-ruby', '1.3.4'

# pinned gems for Centos 7 to remove when no more needed
gem 'nokogiri', '~> 1.13.10'
gem 'rexml'
gem "sparql", "~> 3.3"

# Feature flipping
gem 'flipper'
gem 'flipper-ui'
gem 'flipper-active_record'
gem 'flipper-active_support_cache_store'
# frozen_string_literal: true

require 'test_helper'
require 'minitest/mock'

class CheckResolvabilityHelperTest < ActionView::TestCase
  include CheckResolvabilityHelper

  test 'rejects unsafe URLs before opening a connection' do
    refute_connects do
      result = check_resolvability_helper('http://127.0.0.1/admin', ['text/html'], 1)

      assert_equal 0, result[:result]
      assert_equal blocked_message, result[:status]
    end
  end

  test 'rejects invalid and special-purpose URLs' do
    urls = [
      nil,
      'file:///etc/passwd',
      'http:///resource',
      'http://user:pass@example.com/',
      'http://example/',
      'http://localhost/',
      'http://example.com:0/',
      'http://example.com:65536/',
      'http://[broken/',
      'http://[::1]/',
      # IPv4 private ranges re-encoded as IPv6 (mapped, compatible, and NAT64 forms)
      'http://[::ffff:127.0.0.1]/',
      'http://[::ffff:169.254.169.254]/',
      'http://[::7f00:1]/',
      'http://[64:ff9b::7f00:1]/',
      'http://[64:ff9b:1::7f00:1]/'
    ]

    refute_connects do
      urls.each do |url|
        result = check_resolvability_helper(url, ['text/html'], 1)

        assert_equal 0, result[:result], url.inspect
        assert_equal blocked_message, result[:status], url.inspect
      end
    end
  end

  # A caller able to tell these apart could map internal DNS and network layout.
  test 'does not reveal why a URL was rejected' do
    refute_connects do
      statuses = stub_dns('private.example' => ['10.0.0.5']) do
        [
          check_resolvability_helper('http://private.example/', ['text/html'], 1)[:status],
          check_resolvability_helper('http://nowhere.example/', ['text/html'], 1)[:status],
          check_resolvability_helper('http://[broken/', ['text/html'], 1)[:status]
        ]
      end

      assert_equal [blocked_message] * 3, statuses
    end
  end

  test 'connects to a public address when a hostname also resolves to a private one' do
    stub_dns('mixed.example' => ['93.184.216.34', '10.0.0.5']) do
      stub_http(ok_response) do |_connection, starts|
        result = check_resolvability_helper('http://mixed.example/', ['text/html'], 1)

        assert_equal 1, result[:result]
        assert_equal ['93.184.216.34'], pinned_addresses(starts)
      end
    end
  end

  test 'disables the environment proxy and pins the validated address' do
    stub_dns('public.example' => ['93.184.216.34']) do
      stub_http(ok_response) do |_connection, starts|
        check_resolvability_helper('http://public.example/resource', ['text/html'], 1)

        _host, _port, options = starts.first
        assert_equal '93.184.216.34', options[:ipaddr]
        assert_equal false, options[:proxy_from_env]
        assert_equal 1, options[:open_timeout]
        assert_equal 1, options[:read_timeout]
      end
    end
  end

  test 'revalidates each redirect hop before following it' do
    stub_dns('public.example' => ['93.184.216.34']) do
      stub_http(redirect_response('http://169.254.169.254/latest/meta-data')) do |connection, starts|
        result = check_resolvability_helper('http://public.example/resource', ['text/html'], 1)

        assert_equal 0, result[:result]
        assert_equal blocked_message, result[:status]
        assert_equal 1, connection.requests.size
        assert_equal ['93.184.216.34'], pinned_addresses(starts)
      end
    end
  end

  test 'follows a safe redirect to a successful response' do
    stub_dns('public.example' => ['93.184.216.34'], 'safe.example' => ['93.184.216.35']) do
      stub_http(redirect_response('https://safe.example/final'), ok_response('text/html')) do |connection, starts|
        result = check_resolvability_helper('http://public.example/resource', ['text/html'], 1)

        assert_equal 1, result[:result]
        assert_equal [['public.example', 80], ['safe.example', 443]], starts.map { |host, port, _| [host, port] }
        assert_equal [false, true], starts.map { |_host, _port, options| options[:use_ssl] }
        assert_equal ['93.184.216.34', '93.184.216.35'], pinned_addresses(starts)
        assert_equal [['/resource', 'text/html'], ['/final', 'text/html']], requested(connection)
      end
    end
  end

  test 'follows a relative redirect location' do
    stub_dns('public.example' => ['93.184.216.34']) do
      stub_http(redirect_response('other.html'), ok_response('text/html')) do |connection, _starts|
        result = check_resolvability_helper('http://public.example/docs/resource', ['text/html'], 1)

        assert_equal 1, result[:result]
        assert_equal ['/docs/resource', '/docs/other.html'], connection.requests.map(&:path)
      end
    end
  end

  test 'terminates a redirect without a location' do
    stub_dns('public.example' => ['93.184.216.34']) do
      stub_http(Net::HTTPFound.new('1.1', '302', 'Found')) do |connection, _starts|
        result = check_resolvability_helper('http://public.example/resource', ['text/html'], 1)

        assert_equal 0, result[:result]
        assert_equal '302', result[:status]
        assert_equal 1, connection.requests.size
      end
    end
  end

  test 'reports malformed redirect locations safely' do
    stub_dns('public.example' => ['93.184.216.34']) do
      stub_http(redirect_response('http://[broken')) do |_connection, _starts|
        result = check_resolvability_helper('http://public.example/resource', ['text/html'], 1)

        assert_equal 0, result[:result]
        assert_equal blocked_message, result[:status]
      end
    end
  end

  test 'allows a public hostname on a valid non-default port' do
    stub_dns('public.example' => ['93.184.216.34']) do
      stub_http(ok_response) do |_connection, starts|
        result = check_resolvability_helper('http://public.example:8080/resource', ['text/html'], 1)

        assert_equal 1, result[:result]
        assert_equal [['public.example', 8080]], starts.map { |host, port, _| [host, port] }
        assert_equal ['93.184.216.34'], pinned_addresses(starts)
      end
    end
  end

  test 'uses the unbracketed hostname for public IPv6 literals' do
    stub_http(ok_response) do |_connection, starts|
      result = check_resolvability_helper('http://[2001:4860:4860::8888]/resource', ['text/html'], 1)

      assert_equal 1, result[:result]
      assert_equal [['2001:4860:4860::8888', 80]], starts.map { |host, port, _| [host, port] }
      assert_equal ['2001:4860:4860::8888'], pinned_addresses(starts)
    end
  end

  test 'localizes rejection statuses in French' do
    I18n.with_locale(:fr) do
      result = check_resolvability_helper('http://127.0.0.1/', ['text/html'], 1)

      assert_equal 'URL bloquée', result[:status]
      refute_equal I18n.t('check_resolvability.blocked', locale: :en), result[:status]
    end
  end

  private

  # Stands in for the Net::HTTP instance SsrfFilter yields itself from Net::HTTP.start.
  class FakeConnection
    attr_reader :requests

    def initialize(responses)
      @responses = responses
      @requests = []
    end

    def request(request)
      @requests << request
      @responses.shift || @responses.last
    end
  end

  # SsrfFilter connects via Net::HTTP.start, passing the address it validated as :ipaddr.
  def stub_http(*responses)
    connection = FakeConnection.new(responses)
    starts = []

    Net::HTTP.stub(:start, lambda { |host, port, **options, &block|
      starts << [host, port, options]
      block.call(connection)
    }) do
      yield connection, starts
    end
  end

  def refute_connects
    Net::HTTP.stub(:start, ->(*) { flunk('a connection must not be opened') }) do
      yield
    end
  end

  # SsrfFilter's default resolver reads addresses through Resolv.getaddresses, which
  # answers IP literals from the address itself rather than consulting a resolver.
  def stub_dns(mapping)
    Resolv.stub(:getaddresses, lambda { |host|
      Resolv::AddressRegex.match?(host) ? [host] : mapping.fetch(host) { [] }
    }) { yield }
  end

  def pinned_addresses(starts)
    starts.map { |_host, _port, options| options[:ipaddr] }
  end

  def requested(connection)
    connection.requests.map { |request| [request.path, request['accept']] }
  end

  def ok_response(content_type = nil)
    response = Net::HTTPOK.new('1.1', '200', 'OK')
    response['Content-Type'] = content_type if content_type
    response
  end

  def redirect_response(location)
    response = Net::HTTPFound.new('1.1', '302', 'Found')
    response['Location'] = location
    response
  end

  def blocked_message
    I18n.t('check_resolvability.blocked')
  end
end

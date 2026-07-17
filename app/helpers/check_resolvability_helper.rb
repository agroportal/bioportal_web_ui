require 'benchmark'
require 'net/http'
require 'ssrf_filter'
require 'timeout'
require 'uri'

module CheckResolvabilityHelper

  RESOLVABILITY_ALLOWED_PORT_RANGE = 1..65_535
  RESOLVABILITY_BLOCKED_HOSTNAMES = %w[localhost localhost.localdomain].freeze

  def formats_equivalents(format = nil)
    all = {
      'application/json' => ['application/ld+json'],
      'application/rdf+xml' => %w[application/xml text/xml text/rdf+xml application/octet-stream],
      'text/turtle' => %w[application/turtle application/octet-stream],
      'text/n3' => %w[text/rdf+n3 application/rdf+n3 application/n3 application/n-triples text/n-triples application/ntriples text/ntriples],
      'text/html' => []
    }

    return all unless format

    all[format]
  end

  def resolvability_formats
    formats_equivalents.keys
  end

  def resolvability_timeout
    5
  end

  def resolvability_max_redirections
    10
  end

  def resolvability_status(status, allowed_format, redirections, result: nil, response_time:0)

    supported_format = Array(allowed_format)
    unless result
      supported_format += redirections.map { |k, v| v[:status].to_s.eql?('200') && v[:allowed_format] }.compact
      supported_format.uniq!
      if supported_format.size > 1
        result = 2 # negotiable
      elsif !supported_format.empty?
        result = 1 # resolvable
      end
    end

    { result: result, status: status, allowed_format: supported_format, response_time: response_time, redirections: redirections }
  end

  # Every rejection reports the same opaque message. Saying which check refused a URL
  # would let a caller read back internal DNS and network layout one request at a time.
  def check_resolvability_blocked
    I18n.t('check_resolvability.blocked')
  end

  def public_resolvability_hostname(uri)
    uri.hostname.to_s.downcase.delete_suffix('.')
  end

  def public_resolvability_uri?(uri)
    return false unless uri.is_a?(URI::HTTP) && SsrfFilter::DEFAULT_SCHEME_WHITELIST.include?(uri.scheme)
    return false if uri.userinfo
    return false unless RESOLVABILITY_ALLOWED_PORT_RANGE.cover?(uri.port)

    host = public_resolvability_hostname(uri)
    return false if host.empty?
    return false if RESOLVABILITY_BLOCKED_HOSTNAMES.include?(host) || host.end_with?('.localhost')

    # A bare label can resolve through the resolver's search domains onto an intranet host.
    host.match?(/[.:]/)
  end

  def public_resolvability_uri(url)
    raw_url = url.to_s.strip
    raise ArgumentError, check_resolvability_blocked if raw_url.empty?

    uri = URI.parse(raw_url)
    raise ArgumentError, check_resolvability_blocked unless public_resolvability_uri?(uri)

    uri
  rescue URI::Error
    raise ArgumentError, check_resolvability_blocked
  end

  def public_resolvability_redirect_uri(uri, location)
    location = location.to_s.strip
    raise ArgumentError, check_resolvability_blocked if location.empty?

    joined_uri = begin
      URI.join(uri, location)
    rescue URI::Error
      raise ArgumentError, check_resolvability_blocked
    end

    public_resolvability_uri(joined_uri.to_s)
  end

  def resolvability_ssrf_options(format, timeout_seconds)
    {
      headers: { 'Accept' => format },
      # Redirects are followed here rather than by SsrfFilter so that every hop can be
      # reported, and so that relative locations resolve through URI.join.
      max_redirects: 0,
      allow_unfollowed_redirects: true,
      http_options: {
        open_timeout: timeout_seconds,
        read_timeout: timeout_seconds,
        # Net::HTTP.start proxies from the environment unless told otherwise, which would
        # connect to the proxy instead of the address SsrfFilter validated and pinned.
        proxy_from_env: false
      }
    }
  end

  def resolvability_head(uri, format, timeout_seconds)
    # Guards the DNS lookup, which no Net::HTTP timeout covers.
    Timeout.timeout(timeout_seconds) do
      SsrfFilter.head(uri.to_s, resolvability_ssrf_options(format, timeout_seconds))
    end
  rescue SsrfFilter::Error
    raise ArgumentError, check_resolvability_blocked
  end

  def follow_redirection(url, format, timeout_seconds, redirect_limit = resolvability_max_redirections)
    uri = public_resolvability_uri(url)
    response = nil
    redirect_count = 0
    redirections = [uri]

    total_time = Benchmark.measure do
      until (!response.nil? && !response.is_a?(Net::HTTPRedirection)) || redirect_count >= redirect_limit
        begin
          response = resolvability_head(uri, format, timeout_seconds)
        rescue Timeout::Error
          return resolvability_status('Timeout', [], redirections, result: 0, response_time: timeout_seconds)
        end

        if response.is_a?(Net::HTTPRedirection)
          break if response['location'].to_s.strip.empty?

          uri = public_resolvability_redirect_uri(uri, response['location'])
          redirections << uri
          redirect_count += 1
        end
      end
    end

    if redirect_count >= redirect_limit
      resolvability_status('Too Many Redirections', [], redirections, result: 0, response_time: total_time.real.round(3))
    else
      if response&.code.to_s.eql?('200') && (response&.content_type.to_s.include?(format) || formats_equivalents(format)&.include?(response&.content_type.to_s))
        result = 2
      elsif response&.code.to_s.eql?('200')
        result = 1
      else
        result = 0
      end
      resolvability_status(response&.code, [response&.content_type], redirections, result: result, response_time: total_time.real.round(3))
    end
  end

  def check_resolvability_helper(url, negotiation_formats = resolvability_formats, timeout_seconds = resolvability_timeout)
    redirections = {}
    supported_format = negotiation_formats.find_all do |format|
      begin
        redirections[format] = follow_redirection(url, format, timeout_seconds)
        redirections[format][:result].eql?(2)
      rescue StandardError => e
        redirections[format] = resolvability_status(e.message, [], [], result: 0)
        false
      end
    end

    status = redirections.values.map { |v| v[:status] }.uniq.join(', ')
    average_response_time = redirections.values.sum { |v| v[:response_time] }.fdiv(redirections.size).round(3)
    if supported_format.size > 1
      { result: 2, status: status, allowed_format: supported_format, average_response_time: average_response_time, redirections: redirections }
    elsif status.include?('200')
      returned_format = redirections.map { |k, v| !v[:result].eql?(0) ? v[:allowed_format] : nil }.flatten.compact.uniq
      { result: 1, status: status, allowed_format: returned_format,  average_response_time: average_response_time, redirections: redirections }
    else
      { result: 0, status: status, allowed_format: [],  average_response_time: average_response_time, redirections: redirections }
    end

  end

  def url_resolvable?(result)
    result[:result].eql?(1) || url_content_negotiable?(result)
  end

  def url_content_negotiable?(result)
    result[:result].eql?(2)
  end

  def check_resolvability_success(result)
    url_resolvable?(result) || url_content_negotiable?(result)
  end

  def check_resolvability_message(resolvable, allowed_formats, status, url: nil, response_time: nil)
    supported_format = Array(allowed_formats).compact
    supported_format = allowed_formats.empty? ? 'Format not specified' : supported_format.join(', ')

    if resolvable && (supported_format.size > 1)
      text = t('check_resolvability.check_resolvability_message_1', supported_format: supported_format)
    elsif resolvable
      text = t('check_resolvability.check_resolvability_message_2', supported_format: supported_format)
    else
      text = t('check_resolvability.check_resolvability_message_3', status: status)
    end


    text = text + link_to(', click to see details', check_resolvability_path(url: url), target: '_blank') if url
    text += " (Average response time: #{response_time}s)" if response_time
    text
  end

  # Resolve subject URIs
  def resolve_subject_uri(subject, theme_taxonomy_ontologies)
    # Normalize the subject for consistent caching (e.g., strip whitespace)
    normalized_subject = subject.strip


    text = normalized_subject
    url = normalized_subject

    unless theme_taxonomy_ontologies.empty?
      theme_taxonomy_ontologies.each do |ontology_acronym|
        class_uri = "#{rest_url}/ontologies/#{ontology_acronym}/classes/#{CGI.escape(normalized_subject)}"
        response = LinkedData::Client::HTTP.get(
          class_uri,
          lang: portal_lang,
          display_context: false,
          display_links: false,
          include: "prefLabel"
        )

        if response.prefLabel
          url = class_uri.sub('data.', '')
          text = response.prefLabel
          break
        end
      end
    end

    { text: text, url: url }
  end

end

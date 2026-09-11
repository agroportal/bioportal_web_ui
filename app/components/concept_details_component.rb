# frozen_string_literal: true

class ConceptDetailsComponent < ViewComponent::Base
  include ApplicationHelper
  include OntologiesHelper
  include MultiLanguagesHelper
  include MultiLanguageValues

  renders_one :header, TableComponent
  renders_many :sections, TableRowComponent

  attr_reader :concept_properties

  # How long a property's label is held for. The API answers this lookup with
  # max-age=86400 and no Last-Modified, and the client's own cache stores only
  # what carries one - so the answer is kept here instead. A class page reads a
  # dozen properties and would otherwise pay a request for each, every view.
  PROPERTY_LABEL_TTL = 1.day

  # +reified_keys+ names the rows that hold reified nodes - the raw side of what
  # the Definitions row shows - and are read the same way there as here.
  # +lang+ is the content language those nodes are resolved in.
  def initialize(id:, acronym:, concept_id: nil, properties: nil, top_keys: [], bottom_keys: [], exclude_keys: [],
                 reified_keys: [], lang: 'all')
    @acronym = acronym
    @properties = properties
    @top_keys = top_keys
    @bottom_keys = bottom_keys
    @exclude_keys = exclude_keys
    @reified_keys = reified_keys
    @lang = lang
    @id = id
    @concept_id = concept_id

    @concept_properties = concept_properties2hash(@properties) if @properties
  end

  def add_sections(keys, &block)
    scheme_set = properties_set_by_keys(keys, prefix_properties(concept_properties))
    rows = row_hash_properties(scheme_set, concept_properties, &block)

    rows.each do |row|
      section do |table_row|
        table_row.create(*row)
      end
    end

  end

  def row_hash_properties(properties_set, ontology_acronym, &block)
    out = []
    properties_set&.each do |key, data|
      next if exclude_relation?(key) || !data[:values]

      values = data[:values]
      url = data[:key]
      th = { th: content_tag(:span, row_name(url), title: url, 'data-controller': 'tooltip') }

      if reified_row?(url) && !block_given?
        definitions = definitions_component(values, url, ontology_acronym)
        # Every node in another language: the row holds nothing to read here,
        # exactly as the Definitions row holds nothing.
        next unless definitions.render?

        out << [th, { td: render(definitions) }]
        next
      end

      ajax_links = Array(values).map do |v|
        block_given? ? block.call(v) : row_value(v, ontology_acronym)
      end

      out << [th, { td: list_items_component(max_items: 5) { |r| ajax_links.map { |val| r.container { val.html_safe } } } }]
    end
    out
  end

  # A row whose values are reified nodes, read here the way the Definitions row
  # reads them: the node folded into the text it carries, its raw data a click
  # away rather than its identifier on the page.
  #
  # Named by the caller rather than detected, because resolving a URI costs a
  # request and most rows are full of URIs - a `narrower` with fifty children
  # would pay fifty lookups to learn that not one of them is a node.
  def reified_row?(predicate)
    @reified_keys.any? { |key| predicate.to_s.include?(key) }
  end

  # The values of the row named as reified, read straight from the properties -
  # what the Definitions row should be built from too.
  #
  # That row is otherwise built from the `definition` attribute, and under "all
  # languages" the attribute holds only the literals: the API groups them by
  # language, and a node URI has no language to be grouped under, so it drops
  # out. The properties keep it - under `@none` - and without it the row cannot
  # know which node a sentence was read from, leaving it the one place with no
  # way through to the raw data.
  #
  # Nil unless the row actually holds a node, so that a vocabulary defining its
  # terms in plain literals keeps the attribute it always used: which property
  # counts as the definition is the API's to say, and only a node makes it worth
  # second-guessing.
  def reified_values
    return nil if @reified_keys.empty?

    row = concept_properties&.find { |_, data| data[:values].present? && reified_row?(data[:key]) }
    values = row&.last&.fetch(:values, nil)

    values if normalize_multi_language(values).any? { |item| link?(item[:text]) }
  end

  def definitions_component(values, predicate, ontology_acronym)
    DefinitionsComponent.new(definitions: values, id: "raw-#{predicate.to_s.split(%r{[#/]}).last}",
                             acronym: ontology_acronym, parent_uri: @concept_id, lang: @lang)
  end

  # One value of a row. In a single language it is a plain String; under "all
  # languages" it arrives as a [language, values] pair instead.
  #
  # Either shape can hold URIs, and those have to stay links: a reified node is
  # often language-specific (note_101800en, note_101800fr), so under "all
  # languages" it is a URI *inside* a language pair - which used to fall through
  # to the text rendering and come out unclickable.
  def row_value(value, ontology_acronym)
    return cls_ajax_link(value, ontology_acronym) if value.is_a?(String)

    language, values = value
    values = Array(values)
    return display_in_multiple_languages([value].to_h) unless values.any? && values.all? { |v| v.is_a?(String) && link?(v) }

    safe_join(values.map { |uri| linked_row_value(uri, ontology_acronym, language) })
  end

  # The link, tagged with the language it was read under - the tag the text
  # rendering would have shown.
  def linked_row_value(uri, ontology_acronym, language)
    link = cls_ajax_link(uri, ontology_acronym)
    return link if language.blank? || %w[NONE @NONE].include?(language.to_s.upcase)

    content_tag(:span, class: 'd-inline-flex align-items-center') do
      concat link
      concat content_tag(:span, language.to_s.upcase, class: 'badge badge-secondary ml-1')
    end
  end

  def cls_ajax_link(value, ontology_acronym)
    get_link_for_cls_ajax(value, ontology_acronym, '_blank', parent_id: @concept_id)
  end

  def properties_set_by_keys(keys, concept_properties, exclude_keys = [])
    concept_properties&.select do |k, v|
      (keys.include?(k) || !keys.select { |key| v[:key].to_s.include?(key) }.empty?) && !exclude_keys.include?(k) &&
        exclude_keys.select { |key| v[:key].to_s.include?(key) }.empty?
    end
  end

  def filter_properties(top_keys, bottom_keys, exclude_keys, concept_properties)
    all_keys = concept_properties&.keys || []
    top_set = properties_set_by_keys(top_keys, concept_properties, exclude_keys)
    bottom_set = properties_set_by_keys(bottom_keys, concept_properties, exclude_keys)
    leftover = properties_set_by_keys(all_keys, concept_properties, exclude_keys)
    leftover = leftover.reject { |key, _| top_set.key?(key) || bottom_set.key?(key) }
    [top_set, leftover, bottom_set]
  end

  private

  def link_to_format_modal(format, icon)
    link_to_modal(nil, "/ontologies/#{@acronym}/#{escape(@concept_id)}/serialize/#{format}", { id: "resource_content_#{format}", data: { show_modal_title_value: @concept_id, show_modal_size_value: 'modal-xl' } }) do
      inline_svg("icons/#{icon}.svg", width: '50px', height: '50px')
    end
  end

  def concept_properties2hash(properties)
    # NOTE: example properties
    #
    # properties
    #=> #<struct
    #  http://www.w3.org/2000/01/rdf-schema#label=
    #    [#<struct
    #      object="Etiological thing",
    #      string="Etiological thing",
    #      links=nil,
    #      context=nil>],
    #  http://stagedata.bioontology.org/metadata/def/prefLabel=
    #    [#<struct
    #      object="Etiological thing",
    #      string="Etiological thing",
    #      datatype="http://www.w3.org/2001/XMLSchema#string",
    #      links=nil,
    #      context=nil>],
    #  http://www.w3.org/2000/01/rdf-schema#comment=
    #    [#<struct  object="AD444", string="AD444", links=nil, context=nil>],
    #  http://scai.fraunhofer.de/NDDUO#Synonym=
    #    [#<struct  object="Etiology", string="Etiology", links=nil, context=nil>],
    #  http://www.w3.org/2000/01/rdf-schema#subClassOf=
    #    ["http://www.w3.org/2002/07/owl#Thing"],
    #  http://www.w3.org/1999/02/22-rdf-syntax-ns#type=
    #    ["http://www.w3.org/2002/07/owl#Class"],
    #  links=nil,
    #  context=nil>
    properties_data = {}
    keys = properties.members # keys is an array of symbols
    keys.each do |key|
      next if properties[key].nil? # ignore :context and :links when nil.

      # Shorten the key into a simple label
      k = key.to_s if key.kind_of?(Symbol)
      k ||= key
      label = k.start_with?("http") ? link_last_part(k) : key
      begin
        # Try to simplify the property values, when they are a struct.
        if properties[key].is_a?(OpenStruct)
          values = language_hash(properties[key])
        else
          values = properties[key].map { |v| v.string }
        end
      rescue
        # Each value is probably a simple datatype already.
        values = properties[key]
      end
      data = { :key => key, :values => values }
      properties_data[label] = data
    end
    return properties_data
  end

  # What a raw row is called, named as BioPortal names it: the ontology's own
  # label for the property - "definition", not "IAO_0000115" - and failing that
  # the URI's last segment, with no prefix in front of it.
  def row_name(uri)
    predicate = uri.to_s
    property_label(predicate) || link_last_part(predicate)
  end

  # Nil unless the ontology labels the property: one an imported vocabulary
  # defines is labelled nowhere in the submission, and a lookup the API cannot
  # answer must cost the row its name and not the page.
  def property_label(uri)
    Rails.cache.fetch(["property_label", @acronym, uri], expires_in: PROPERTY_LABEL_TTL) do
      LinkedData::Client::HTTP.get("/ontologies/#{@acronym}/properties/#{CGI.escape(uri)}/label").label.presence
    end
  rescue StandardError => e
    Rails.logger.warn("Property label lookup failed for #{uri} in #{@acronym}: #{e.message}")
    nil
  end

  def exclude_relation?(relation_to_check, ontology = nil)
    excluded_relations = ["type", "rdf:type", "[R]", "SuperClass", "InstanceCount"]

    # Show or hide property based on the property and ontology settings
    if ontology
      # TODO_REV: Handle obsolete classes
      # Hide owl:deprecated if a user has set class or property based obsolete checking
      # if !ontology.obsoleteParent.nil? && relation_to_check.include?("owl:deprecated") || !ontology.obsoleteProperty.nil? && relation_to_check.include?("owl:deprecated")
      #   return true
      # end
    end

    excluded_relations.each do |relation|
      return true if relation_to_check.is_a?(Array) && relation_to_check.include?(relation)
    end
    return false
  end

  def convert_dates(hash)
    hash.transform_values do |property|
      if property[:key].to_s.include?("http://purl.org/dc/terms/created") || property[:key].to_s.include?("http://purl.org/dc/terms/modified")
        value = property[:values].first
        parsed_date = l(Date.parse(value), format: :monthfull_day_year.to_sym) rescue value
        property[:values] = [parsed_date]
      end
      property
    end
  end

end

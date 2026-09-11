module SubmissionFilter
  extend ActiveSupport::Concern

  include FederationHelper

  BROWSE_ATTRIBUTES = ['ontology', 'submissionStatus', 'description', 'pullLocation', 'creationDate',
                       'contact', 'released', 'naturalLanguage', 'hasOntologyLanguage',
                       'hasFormalityLevel', 'isOfType', 'deprecated', 'status', 'metrics']

  ONTOLOGY_FORMATS = %w[OBO OWL SKOS UMLS XLSX].freeze

  RETIRED_STATUS = 'retired'

  # Browse has two states only: retired ontologies are hidden, or shown alone.
  RETIRED_HIDDEN = :hidden
  RETIRED_ONLY = :only

  def init_filters(params)
    @show_views = params[:show_views]&.eql?('true')
    @show_private_only = params[:private_only]&.eql?('true')
    @user_ontologies_only = params[:user_ontologies_only]&.eql?('true')
    @show_public_only = params[:public_only]&.eql?('true')
    @show_retired = params[:show_retired]&.eql?('true')
    @selected_format = params[:format]
    @sort_by = params[:sort_by].blank? ? 'visits' : params[:sort_by]
    @search = params[:search]
  end

  def submissions_paginate_filter(params)
    request_params = filters_params(params, page: params[:page], pagesize: 10)
    filter_params = params.permit(@filters.keys).to_h
    init_filters(params)

    @analytics = Rails.cache.fetch("ontologies_analytics-#{Time.now.year}-#{Time.now.month}-#{request_portals.join('-')}") do
      helpers.ontologies_analytics
    end

    @ontologies = LinkedData::Client::Models::Ontology.all(include: 'all', also_include_views: true, display_links: false, display_context: false)

    @ontologies, @errors = @ontologies.partition { |x| !x.errors }

    # get fair scores of all ontologies, including from the selected federated portals
    @fair_scores = fairness_service_enabled? ? get_fair_score_with_federation('all') : nil

    @total_ontologies = @ontologies.size

    params = { query: @search,
               retired: request_params[:retired],
               show_views: @show_views,
               private_only: @show_private_only,
               user_ontologies_only: @user_ontologies_only,
               languages: request_params[:naturalLanguage],
               page_size: @total_ontologies,
               formality_level: request_params[:hasFormalityLevel],
               is_of_type: request_params[:isOfType],
               groups: request_params[:group], categories: request_params[:hasDomain],
               formats: request_params[:hasOntologyLanguage] }

    submissions = filter_submissions(@ontologies, **params)

    submissions = merge_by_acronym(submissions) if federation_enabled?


    submissions = sort_submission_by(submissions, @sort_by, @search)

    @page = paginate_submissions(submissions, request_params[:page].to_i, request_params[:pagesize].to_i)

    count = @page.page.eql?(1) ? count_objects(submissions) : {}

    federation_counts = federated_browse_counts(submissions)

    [@page.collection, @page.totalCount, count, filter_params, federation_counts]
  end

  def ontologies_with_filters_url(filters, page: 1, count: false)
    helpers.ontologies_with_filters_url(filters, page: page, count: count)
  end

  private

  def merge_by_acronym(submissions)
    merged_submissions = []
    submissions.group_by { |x| x[:ontology]&.acronym }.each do |acronym, ontologies|
      ontology = canonical_ontology(ontologies)
      ontology[:sources] = ontologies.map { |x| x[:id] }
      ontology[:sources].reject! { |id| id.include?(portal_name.downcase) } if ontology[:sources].size.eql?(1)
      merged_submissions << ontology
    end
    merged_submissions
  end


  def filter_submissions(ontologies, query:, retired:, show_views:, private_only:, public_only: false, user_ontologies_only: false, languages:, page_size:, formality_level:, is_of_type:, groups:, categories:, formats:, user: false)
    if user
      # Getting only the submission of the logged in user
      submissions = LinkedData::Client::Models::OntologySubmission.all(acronym: ontologies.map { |o| o[:acronym] }.join('|'), include: BROWSE_ATTRIBUTES.join(','), include_status: "ANY", also_include_views: true, display_links: false, display_context: false)    
    else
      status_to_include = current_user_admin? ? "ANY" : "READY"
      submissions = LinkedData::Client::Models::OntologySubmission.all(include: BROWSE_ATTRIBUTES.join(','), include_status: status_to_include, also_include_views: true, display_links: false, display_context: false)
    end

    submissions = submissions.map { |x| x[:ontology] ? [x[:ontology][:id], x] : nil }.compact.to_h

    submissions = ontologies.map { |ont| ontology_hash(ont, submissions) }

    submissions.map do |s|
      out = true
      out &&= s[:ontology].viewingRestriction.eql?('private') if private_only
      out &&= s[:ontology].viewingRestriction.eql?('public') if public_only
      out &&= s[:ontology].administeredBy.include?(current_user.id) if user_ontologies_only
      out &&= (groups.blank? || (s[:ontology].group.map { |x| helpers.link_last_part(x) } & groups.split(',')).any?)
      out &&= (categories.blank? || (s[:ontology].hasDomain.map { |x| helpers.link_last_part(x) } & categories.split(',')).any?)
      out &&= status_visible?(s[:status], retired)
      out &&= (formats.blank? || formats.split(',').any? { |f| s[:hasOntologyLanguage].eql?(f) })
      out &&= (is_of_type.blank? || is_of_type.split(',').any? { |f| helpers.link_last_part(s[:isOfType]).eql?(f) })
      out &&= (formality_level.blank? || formality_level.split(',').any? { |f| helpers.link_last_part(s[:hasFormalityLevel]).eql?(f) })
      out &&= (languages.blank? || languages.split(',').any? { |f| Array(s[:naturalLanguage]).any? { |n| helpers.link_last_part(n).eql?(f) } })
      out &&= (s[:ontology].viewOf.blank? || (show_views && !s[:ontology].viewOf.blank?))

      out &&= (query.blank? || [s[:description], s[:ontology].name, s[:ontology].acronym].any? { |x| (x || '').downcase.include?(query.downcase) })

      if out
        s[:rank] = 0

        next s if query.blank?

        s[:rank] += 3 if s[:ontology].acronym && s[:ontology].acronym.downcase.include?(query.downcase)

        s[:rank] += 2 if s[:ontology].name && s[:ontology].name.downcase.include?(query.downcase)

        s[:rank] += 1 if s[:description] && s[:description].downcase.include?(query.downcase)

        s
      else
        nil
      end

    end.compact
  end

  # Filter on the retired status alone rather than on a whitelist of known ones:
  # an ontology whose submission failed to parse carries no status at all, and
  # values outside the enum do get stored, so a whitelist left both unreachable
  # through every filter combination. See issue #1202.
  def status_visible?(status, retired)
    is_retired = status.to_s.eql?(RETIRED_STATUS)

    retired.eql?(RETIRED_ONLY) ? is_retired : !is_retired
  end

  def paginate_submissions(all_submissions, page, size)
    current_page = page
    page_size = size

    start_index = (current_page - 1) * page_size
    end_index = start_index + page_size - 1
    next_page = current_page * page_size < all_submissions.size ? current_page + 1 : nil
    OpenStruct.new(page: current_page, nextPage: next_page, totalCount: all_submissions.size,
                   collection: all_submissions[start_index..end_index])
  end

  def sort_submission_by(submissions, sort_by, query = nil)
    return submissions.sort_by { |x| x[:rank] ? -x[:rank] : 0 } unless query.blank?

    if sort_by.eql?('visits')
      submissions = submissions.sort_by { |x| -(x[:popularity] || 0) }
    elsif sort_by.eql?('fair')
      submissions = submissions.sort_by { |x| -x[:fairScore] }
    elsif sort_by.eql?('notes')
      submissions = submissions.sort_by { |x| -x[:note_count] }
    elsif sort_by.eql?('projects')
      submissions = submissions.sort_by { |x| -x[:project_count] }
    elsif sort_by.eql?('metrics_classes')
      submissions = submissions.sort_by { |x| -x[:class_count] }
    elsif sort_by.eql?('metrics_individuals')
      submissions = submissions.sort_by { |x| -x[:individual_count] }
    elsif sort_by.eql?('creationDate')
      submissions = submissions.sort_by { |x| x[:creationDate] || '' }.reverse
    elsif sort_by.eql?('released')
      submissions = submissions.sort_by { |x| x[:released] || '' }.reverse
    elsif sort_by.eql?('ontology_name')
      submissions = submissions.sort_by { |x| -x[:name] }
    end
    submissions
  end

  def filters_params(params, includes: BROWSE_ATTRIBUTES.join(','), page: 1, pagesize: 5)
    request_params = { display_links: false, display_context: false,
                       include: includes, include_status: 'RDF' }
    request_params.merge!(page: page.to_i, pagesize: pagesize.to_i) if page
    filters_values_map = {
      categories: :hasDomain,
      groups: :group,
      naturalLanguage: :naturalLanguage,
      isOfType: :isOfType,
      format: :hasOntologyLanguage,
      hasFormalityLevel: :hasFormalityLevel,
      search: %i[name acronym description],
      sort_by: :order_by
    }

    filters_boolean_map = {
      show_views: { api_key: :also_include_views, default: 'true' },
      public_only: { api_key: :viewingRestriction, default: 'public' },
      user_ontologies_only: { api_key: :administeredBy, default: 'true' },
      private_only: { api_key: :viewingRestriction, default: 'private' }
    }
    @filters = {}

    filters_boolean_map.each do |k, v|
      next unless params[k].eql?('true') || params[k].eql?(v[:default])

      @filters.merge!(k => v[:default])
      request_params.merge!(v[:api_key] => v[:default])
    end

    if params[:show_retired].blank?
      request_params[:retired] = RETIRED_HIDDEN
    else
      request_params[:retired] = RETIRED_ONLY
      @filters[:show_retired] = 'true'
    end

    filters_values_map.each do |filter, api_key|
      next if params[filter].nil? || params[filter].empty?

      @filters.merge!(filter => params[filter])
      Array(api_key).each do |key|
        request_params.merge!(key => params[filter])
      end
    end

    unless params[:sort_by].blank?
      @filters[:sort_by] = params[:sort_by]
    end

    unless params[:search].blank?
      @filters[:search] = params[:search]
    end

    unless params[:portals].blank?
      @filters[:portals] = params[:portals]
    end

    request_params.delete(:order_by) if %w[visits fair].include?(request_params[:sort_by].to_s)
    request_params
  end

  def ontology_hash(ont, submissions)
    o = {}
    sub = submissions[ont.id]

    o[:ontology] = ont

    add_ontology_attributes(o, ont)
    add_submission_attributes(o, sub)
    add_fair_score_metrics(o, ont)

    o[:hasOntologyLanguage] = sub&.hasOntologyLanguage

    if sub&.metrics && !sub.metrics.is_a?(String)
      o[:class_count] = sub.metrics.classes
      o[:individual_count] = sub.metrics.individuals
    else
      o[:class_count] = 0
      o[:individual_count] = 0
    end
    o[:class_count_formatted] = number_with_delimiter(o[:class_count], delimiter: ',')
    o[:individual_count_formatted] = number_with_delimiter(o[:individual_count], delimiter: ',')

    o[:note_count] = ont.notes&.length || 0
    o[:project_count] = ont.projects&.length || 0
    o[:popularity] = @analytics[ont.id.split('/').last.to_s] || 0
    o[:rank] = sub ? sub[:rank] : 0

    o
  end

  def add_submission_attributes(ont_hash, sub)
    return if sub.nil?

    ont_hash[:submissionStatus] = sub.submissionStatus
    ont_hash[:deprecated] = sub.deprecated
    ont_hash[:status] = sub.status
    ont_hash[:submission] = true
    ont_hash[:pullLocation] = sub.pullLocation
    ont_hash[:description] = sub.description
    ont_hash[:creationDate] = sub.creationDate
    ont_hash[:released] = sub.released
    ont_hash[:naturalLanguage] = sub.naturalLanguage
    ont_hash[:hasFormalityLevel] = sub.hasFormalityLevel
    ont_hash[:isOfType] = sub.isOfType
    ont_hash[:submissionStatusFormatted] = submission_status2string(sub).gsub(/\(|\)/, '')
    ont_hash[:format] = sub.hasOntologyLanguage&.split('/').last
    ont_hash[:contact] = sub.contact.map { |c| c.is_a?(String) ? c.split('|').first : c.name }.first unless sub.contact.nil?
  end

  def add_ontology_attributes(ont_hash, ont)
    return if ont.nil?

    ont_hash[:id] = ont.id
    ont_hash[:type] = ont.viewOf.nil? ? 'ontology' : 'ontology_view'
    ont_hash[:show] = ont.viewOf.nil? ? true : false # show ontologies only by default
    ont_hash[:groups] = ont.group || []
    ont_hash[:categories] = ont.hasDomain || []
    ont_hash[:private] = ont.private?
    ont_hash[:submissionStatus] = []
    ont_hash[:administeredBy] = ont.administeredBy
    ont_hash[:name] = ont.name
    ont_hash[:acronym] = ont.acronym
    ont_hash[:projects] = ont.projects
    ont_hash[:notes] = ont.notes
    ont_hash[:viewOfOnt] = ont.viewOf
  end

  def add_fair_score_metrics(ont_hash, ont)
    if !@fair_scores.nil? && !@fair_scores[ont.acronym].nil?
      ont_hash[:fairScore] = @fair_scores[ont.acronym]['score']
      ont_hash[:normalizedFairScore] = @fair_scores[ont.acronym]['normalizedScore']
    else
      ont_hash[:fairScore] = 0
      ont_hash[:normalizedFairScore] = 0
    end
  end

  def ontology_filters_init(categories, groups)
    @languages = submission_metadata.select { |x| x['@id']['naturalLanguage'] }.first['enforcedValues'].map do |id, name|
      { 'id' => id, 'name' => name, 'value' => id.split('/').last, 'acronym' => name }
    end

    @formalityLevel = submission_metadata.select { |x| x['@id']['hasFormalityLevel'] }.first['enforcedValues'].map do |id, name|
      { 'id' => id, 'name' => helpers.link_last_part(id), 'acronym' => name, 'value' => helpers.link_last_part(id) }
    end

    @isOfType = submission_metadata.select { |x| x['@id']['isOfType'] }.first['enforcedValues'].map do |id, name|
      { 'id' => id, 'name' => helpers.link_last_part(id), 'acronym' => name, 'value' => helpers.link_last_part(id) }
    end

    @formats = [[t("submissions.filter.all_formats"), '']] + ONTOLOGY_FORMATS
    @sorts_options = [
      [t("submissions.filter.sort"), ''],
      [t("submissions.filter.sort_by_name"), 'ontology_name'],
      [t("submissions.filter.sort_by_classes"), 'metrics_classes'],
      [t("submissions.filter.sort_by_instances_concepts"), 'metrics_individuals'],
      [t("submissions.filter.sort_by_submitted_date"), 'creationDate'],
      [t("submissions.filter.sort_by_creation_date"), 'released'],
      [t("submissions.filter.sort_by_fair_score"), 'fair'],
      [t("submissions.filter.sort_by_popularity"), 'visits'],
      [t("submissions.filter.sort_by_notes"), 'notes'],
      [t("submissions.filter.sort_by_projects"), 'projects'],
    ]

    init_filters(params)
    # @missingStatus = [
    #   {'id' => 'RDF', 'name' => 'RDF', 'acronym' => 'RDF'},
    #   {'id' => 'ABSOLETE', 'name' => 'ABSOLETE', 'acronym' => 'ABSOLETE'},
    #   {'id' => 'METRICS', 'name' => 'METRICS', 'acronym' => 'METRICS'},
    #   {'id' => 'RDF_LABELS', 'name' => 'RDF LABELS', 'acronym' => 'RDFLABELS'},
    #   {'id' => 'UPLOADED', 'name' => 'UPLOADED', 'acronym' => 'UPLOADED'},
    #   {'id' => 'INDEXED_PROPERTIES', 'name' => 'INDEXED PROPERTIES', 'acronym' => 'INDEXED_PROPERTIES'},
    #   {'id' => 'ANNOTATOR', 'name' => 'ANNOTATOR', 'acronym' => 'ANNOTATOR'},
    #   {'id' => 'DIFF', 'name' => 'DIFF', 'acronym' => 'DIFF'}
    # ]

    {
      categories: object_filter(categories, :categories),
      groups: object_filter(groups, :groups),
      naturalLanguage: object_filter(@languages, :naturalLanguage, "value"),
      hasFormalityLevel: object_filter(@formalityLevel, :hasFormalityLevel),
      isOfType: object_filter(@isOfType, :isOfType, "value"),
      # missingStatus: object_filter(@missingStatus, :missingStatus)
    }
  end

  def check_id(name_value, objects, name_key)
    selected_category = objects.select { |x| x[name_key].parameterize.underscore.eql?(name_value.parameterize.underscore) }
    selected_category.first && selected_category.first['id']
  end


  def object_filter(objects, object_name, name_key = 'acronym')
    checks = params[object_name]&.split(',') || []
    checks = checks.map { |x| helpers.link_last_part(check_id(x, objects, name_key)) }.compact

    objects.uniq! { |x| helpers.link_last_part(x['id']) }
    ids = objects.map { |x| helpers.link_last_part(x['id']) }
    count = ids.count { |x| checks.include?(x) }

    [objects, checks, count]
  end

  def count_objects(ontologies)
    objects_count = {}
    @categories = LinkedData::Client::Models::Category.all(display_links: false, display_context: false)
    @groups = LinkedData::Client::Models::Group.all(display_links: false, display_context: false)

    @filters = ontology_filters_init(@categories, @groups)
    object_names = @filters.keys

    @filters.each do |filter, values|
      objects = values.first
      objects_count[filter] = objects.map { |v| [v['id'], 0] }.to_h
    end

    ontologies.each do |ontology|
      object_names.each do |name|
        values = Array(ontology[name])
        values.each do |v|
          v = helpers.link_last_part(v)

          objects_count[name] = {} unless objects_count[name]
          objects_count[name][v] = (objects_count[name][v] || 0) + 1
        end
      end
    end
    objects_count
  end

end

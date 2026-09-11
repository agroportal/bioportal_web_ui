class MyOntologiesController < ApplicationController
  include FairScoreHelper
  include ActionView::Helpers::NumberHelper
  include OntologyUpdater
  include SubmissionFilter

  require 'multi_json'
  require 'cgi'

  helper :concepts
  helper :fair_score

  layout 'ontology'

  before_action :authorize_and_redirect, :only => [:index, :user_ontologies_filter]

  # GET /my-ontologies
  def index
    @filters = ontology_filters_init()
  end

  def user_ontologies_filter
    init_filters(params)

    @time = Benchmark.realtime do
      @page = user_submissions_paginate_filter(params)
    end

    @ontologies = @page.collection
    @count = @page.totalCount
    counted_objects = @page.page.eql?(1) ? count_objects(@ontologies) : {}

    streams = if @page.page.eql?(1)
                [
                  prepend("ontologies_list_view-page-#{@page.page}", partial: "my_ontologies/user_ontologies"),
                  *render_filter_counts(counted_objects)
                ]
              else
                [
                  replace("ontologies_list_view-page-#{@page.page}", partial: "my_ontologies/user_ontologies")
                ]
              end

    render turbo_stream: streams
  end

  private

  # --- Core data fetch ---
  def user_submissions_paginate_filter(params)
    request_params = filters_params(params, page: params[:page], pagesize: 10)
    filter_params  = params.permit(@filters.keys).to_h

    user_created_ontologies = fetch_user_ontologies
    @analytics = {}
    submissions = []

    unless user_created_ontologies.empty?
      @fair_scores = fairness_service_enabled? ? get_fair_score("all") : nil
      submissions = filter_submissions(user_created_ontologies, **build_filter_options(request_params), user: true)
      submissions = merge_by_acronym(submissions) if federation_enabled?
      submissions = sort_submission_by(submissions, @sort_by, @search)
    end

    page = paginate_submissions(submissions, request_params[:page].to_i, request_params[:pagesize].to_i)
    page
  end

  def fetch_user_ontologies
    user_ontologies_url = "#{LinkedData::Client.settings.rest_url}/users/#{current_user.username}/ontologies"
    @ontologies = LinkedData::Client::HTTP.get(user_ontologies_url, {"display_links": false, "display_context": false})
    @total_ontologies   = @ontologies.size
    @ontologies
  end

  def build_filter_options(request_params)
    {
      query: @search,
      retired: request_params[:retired],
      show_views: @show_views,
      public_only: @show_public_only,
      private_only: @show_private_only,
      languages: request_params[:naturalLanguage],
      page_size: @total_ontologies,
      formality_level: request_params[:hasFormalityLevel],
      is_of_type: request_params[:isOfType],
      groups: request_params[:group],
      categories: request_params[:hasDomain],
      formats: request_params[:hasOntologyLanguage]
    }
  end

  # --- Filters ---
  def ontology_filters_init
    ## formats and sorts_options is for the filters in the search bar
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
    languages = fetch_metadata_values("naturalLanguage")
    formality_level = fetch_metadata_values("hasFormalityLevel")
    is_of_type = fetch_metadata_values("isOfType")

    {
      naturalLanguage: object_filter(languages, :naturalLanguage, "value"),
      hasFormalityLevel: object_filter(formality_level, :hasFormalityLevel),
      isOfType: object_filter(is_of_type, :isOfType, "value")
    }
  end

  def fetch_metadata_values(key)
    item = submission_metadata.find { |x| x["@id"][key] }
    return [] unless item

    item["enforcedValues"].map do |id, name|
      {
        "id" => id,
        "name" => helpers.link_last_part(id),
        "value" => helpers.link_last_part(id),
        "acronym" => name
      }
    end
  end

  # --- Counts ---
  def count_objects(ontologies)
    objects_count = {}
    @filters = ontology_filters_init()
    @filters.each do |filter, values|
      objects = values.first
      objects_count[filter] = objects.to_h { |v| [v["id"], 0] }
    end
    ontologies.each do |ontology|
      @filters.keys.each do |name|
        Array(ontology[name]).each do |v|
          v = helpers.link_last_part(v)
          objects_count[name][v] = (objects_count[name][v] || 0) + 1
        end
      end
    end

    objects_count
  end

  # --- UI helpers ---
  def render_filter_counts(counted_objects)
    counted_objects.flat_map do |section, values_count|
      values_count.map do |value, count|
        replace("count_#{section}_#{link_last_part(value)}") do
          helpers.turbo_frame_tag("count_#{section}_#{link_last_part(value)}") do
            helpers.content_tag(:span, count.to_s, class: "hide-if-loading #{count.zero? ? 'disabled' : ''}")
          end
        end
      end
    end
  end

end

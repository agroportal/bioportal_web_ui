class AgentsController < ApplicationController
  include TurboHelper, AgentHelper, ApplicationHelper
  
  before_action :check_agents_enabled
  before_action :authorize_and_redirect, :only => [:edit, :update, :create, :new]
  layout :determine_layout, only: [:index, :details]

  def index
    # Deep link target for the "browse all agents" action of the site-wide
    # search box; the table itself still filters through /ajax/agents/list.
    @search = params[:search].to_s
    # /agents?page=14 lands on the 14th page; the table normalises anything else.
    @page = params[:page].to_i
  end

  def details
    @agent = find_agent(params[:id])
    @title = @agent.acronym || @agent.name
    not_found(t('agents.not_found_agent', id: params[:id])) if @agent.status == 404

    @agent_stats = AgentStatisticsCalculatorComponent.new(@agent).stats

    mapping = {
      'http://omv.ontoware.org/2005/05/ontology#hasContributor' => 'Contributor',
      'http://omv.ontoware.org/2005/05/ontology#hasCreator' => 'Creator',
      'http://purl.org/dc/terms/publisher' => 'Publisher',
      'http://xmlns.com/foaf/0.1/fundedBy' => 'Funded By',
      'http://schema.org/copyrightHolder' => 'Copyright Holder',
      'http://schema.org/translator' => 'Translator',
      'http://omv.ontoware.org/2005/05/ontology#endorsedBy' => 'Endorsed By',
      'http://purl.org/pav/curatedBy' => 'Curated By'
    }

    @agentOntologies = @agent.usages.to_h.each_with_object({}) do |(key, value), hash|
      if (match = key.to_s.match(%r{/ontologies/([^/]+)/submissions}))
        ontology_acronym = match[1]
        hash[ontology_acronym] = value.map { |url| mapping[url] }
      end
    end
  end

  def show
    @agent = LinkedData::Client::Models::Agent.find(params[:agent_id].split('/').last)
    not_found(t('agents.not_found_agent', id: params[:agent_id])) if @agent.nil?

    @agent_id = params[:id] || agent_id(@agent)
    @name_prefix = params[:name_prefix]
    @editable = params[:editable]&.eql?('true')
    @edit_on_modal = params[:edit_on_modal]&.eql?('true')
    @deletable = params[:deletable]&.eql?('true')
  end

  def find_agent(id = params[:id], include_params = 'all')
    id = helpers.unescape(id)
    @agent = LinkedData::Client::Models::Agent.find(id.split('/').last, { include: include_params })
    not_found("Agent with id #{id} not found") if @agent.nil? || @agent.errors
    @agent
  end

  def ajax_agents_list
    page = params[:page] || 1
    page_size = params[:pagesize].to_i
    query = params[:search].presence

    # Fetch agents based on search query or pagination
    agents = if query
      search_agents(query, options: { page: page, pagesize: page_size })
    else
      fetch_paginated_agents(page, page_size)
    end

    # Prepare data for response
    render json: {
      collection: prepare_agent_data(agents.collection),
      recordsTotal: agents.totalCount,
      recordsFiltered: agents.totalCount
    }
  end
  
  

  def search_agents(query, options: { page: 1, pagesize: 10 })
    filters = {
      query: "#{query}*",
      qf: "identifiers_texts^20 acronym_text^15 name_text^10 email_text^10",
      page: options[:page],
      pagesize: options[:pagesize],
    }
    LinkedData::Client::HTTP.get('/search/agents', filters)
  end

  def ajax_agents
    query = params[:query].presence
    if query
      agents = search_agents(query)
    end
    agents_json = agents.collection.map do |agent
      |
      {
        id: agent.id,
        name: agent.name,
        type: agent.agentType,
        # The agents Solr core is searchable on identifiers_texts but does not
        # store identifiers, so this is always empty regardless of `include`.
        # The key stays so the row template's placeholder still gets cleared.
        identifiers: agent.identifiers&.join(', '),
        acronym: agent.acronym
      }
    end

    render json: agents_json
  end

  def new
    @agent = LinkedData::Client::Models::Agent.new
    @agent.id = params[:id]
    @agent.creator = session[:user].id
    @agent.agentType = params[:type] || 'person'
    @agent.name = params[:name]
    @name_prefix = params[:name_prefix] || ''
    @show_affiliations = params[:show_affiliations].nil? || params[:show_affiliations]&.eql?('true')
    @deletable = params[:deletable]&.eql?('true')
    render 'agents/new', layout: nil
 
  end

  def create
    new_agent = save_agent(agent_params)
    parent_id = params[:parent_id]
    name_prefix = params[:name_prefix]
    alert_id = agent_id_alert_container_id(params[:id], parent_id)
    deletable = params[:deletable]&.eql?('true')
    if new_agent.errors
      errors = generate_errors(response_errors(new_agent))
      render_turbo_stream alert_error(id: alert_id) { errors.join(', ') }
    else
      success_message = t('agents.add_agent')
      streams = [alert_success(id: alert_id) { success_message }]

      streams << prepend('agents-table_table_body', partial: 'agents/agent', locals: { agent: new_agent })
      streams << replace_agent_form(new_agent, agent_id: nil, frame_id: params[:id],
                                    parent_id: parent_id, name_prefix: name_prefix,
                                    deletable: deletable
      ) if params[:parent_id]

      render_turbo_stream(*streams)
    end
  end

  def edit
    @agent = LinkedData::Client::Models::Agent.find(params[:id].split('/').last)
    @name_prefix = params[:name_prefix] || ''
    @show_affiliations = params[:show_affiliations].nil? || params[:show_affiliations].eql?('true')
    @deletable = params[:deletable].to_s.eql?('true')
    render 'agents/edit', layout: nil
  end

  def show_search
    id = params[:id]
    parent_id = params[:parent_id]
    name_prefix = params[:name_prefix]
    agent_type = params[:agent_type]
    agent_editable = params[:editable]&.eql?('true')
    agent_deletable = params[:deletable].to_s.eql?('true')

    attribute_template_output = helpers.agent_search_input(id, agent_type,
                                                           parent_id: parent_id,
                                                           name_prefix: name_prefix,
                                                           editable: agent_editable,
                                                           deletable: agent_deletable)
    render_turbo_stream(replace(helpers.agent_id_frame_id(id, parent_id)) {  render_to_string(inline: attribute_template_output) } )

  end

  def update
    agent_update, agent = update_agent(params[:id].split('/').last, agent_params)

    parent_id = params[:parent_id]
    alert_id = agent_alert_container_id(agent, parent_id)
    deletable = params[:deletable]&.eql?('true')
    if response_error?(agent_update)
      errors = generate_errors(response_errors(agent_update).values.first)
      render_turbo_stream alert_error(id: alert_id) { errors.join(', ') }
    else
      success_message = t('agents.update_agent')
      table_line_id = agent_table_line_id(agent_id(agent))
      agent = find_agent(agent.id.split('/').last)
      streams = [alert_success(id: alert_id) { success_message },
                 replace(table_line_id, partial: 'agents/agent', locals: { agent: agent })
      ]

      streams << replace_agent_form(agent, agent_id: agent_id(agent.id), name_prefix: params[:name_prefix] , parent_id: parent_id, editable: true, deletable: deletable) if params[:parent_id]

      render_turbo_stream(*streams)
    end
  end

  def agent_usages
    @agent = find_agent(params[:id], include_params = 'usages')
    not_found(t('agents.not_found_agent', id: params[:id])) if @agent.nil? || @agent.errors
    @ontology_acronyms = LinkedData::Client::Models::Ontology.all(include: 'acronym', display_links: false, display_context: false, include_views: true).map(&:acronym)
    render partial: 'agents/agent_usage'
  end

  def update_agent_usages
    agent = find_agent(params[:id])
    responses, new_usages = update_agent_usages_action(agent, agent_usages_params)
    parent_id = params[:parent_id]
    alert_id = agent_alert_container_id(agent, parent_id)


    if responses.values.any? { |x| response_error?(x) }
      errors = {}
      responses.each do |ont, response|
        errors[ont.acronym] = response_errors(response) if response_error?(response)
      end

      render_turbo_stream(alert_error(id: alert_id) { helpers.agent_usage_errors_display(errors) })
    else

      success_message = t('agents.agent_usages_updated')
      table_line_id = agent_table_line_id(agent_id(agent))
      agent.usages = new_usages
      streams = [alert_success(id: alert_id) { success_message },
                 replace(table_line_id, partial: 'agents/agent', locals: { agent: agent })
      ]

      render_turbo_stream(*streams)
    end

  end

  def destroy
    error = nil
    @agent = LinkedData::Client::Models::Agent.find(params[:id].split('/').last)
    success_text = ''

    if @agent.nil?
      success_text = t('agents.agent_already_deleted', id: params[:id])
    else
      error_response = @agent.delete

      if response_error?(error_response)
        error = response_errors(error_response)
      else
        success_text = t('agents.agent_deleted_successfully', id: params[:id])
      end
    end

    respond_to do |format|
      format.turbo_stream do
        if error.nil?
          render turbo_stream: [
            alert(type: 'success') { success_text },
            turbo_stream.remove(agent_table_line_id(params[:id]))
          ]

        else
          render_turbo_stream alert(type: 'danger') { error }
        end
      end
      format.html { render json: { success: success_text, error: error } }
    end

  end

  private
  def fetch_paginated_agents(page, page_size)
    options = { 
      page: page, 
      include: 'agentType,name,homepage,acronym,email,identifiers,affiliations,usages' 
    }
    
    # Only set page size if it's not -1 (which typically means "all")
    options[:pagesize] = page_size if page_size > 0
    
    LinkedData::Client::Models::Agent.all(options).first
  end
  
  # Normalize agent data structure to handle different response formats (This will be improved after the agents search endpoint is finished)
  def normalize_agent(agent)
    OpenStruct.new(
      id: agent.id,
      name: agent.respond_to?(:name) ? agent.name : agent.name_text,
      acronym: agent.respond_to?(:acronym) ? agent.acronym : nil,
      agentType: agent.respond_to?(:agentType) ? agent.agentType : agent.agentType_t,
      affiliations: agent.respond_to?(:affiliations) ? agent.affiliations : [],
      identifiers: agent.respond_to?(:identifiers) ? agent.identifiers : [],
      usages: agent.respond_to?(:usages) ? agent.usages : []
    )
  end
  
  # Process collection of agents into format needed for the frontend
  def prepare_agent_data(collection)
    partial_path = "agents/table"
    
    collection.map do |agent|
      normalized_agent = normalize_agent(agent)
      
      {
        id: "#{agent.id.split('/').last}_agent_table_item",
        name: render_agent_partial("#{partial_path}/name", normalized_agent),
        acronym: normalized_agent.acronym,
        agentType: normalized_agent.agentType,
        affiliations: render_agent_partial("#{partial_path}/affiliations", normalized_agent),
        usages: render_agent_partial("#{partial_path}/usages", normalized_agent),
        actions: render_agent_partial("#{partial_path}/actions", normalized_agent)
      }
    end
  end

  def replace_agent_form(agent, agent_id: nil, frame_id: nil, parent_id:, partial: 'agents/agent_show', name_prefix: '', editable: true, deletable: true)

    frame_id = frame_id ? agent_id_frame_id(frame_id, parent_id) : agent_frame_id(agent, parent_id)

    replace(frame_id, partial: partial, layout: false ,
            locals: { agent_id: agent_id, agent: agent, name_prefix: name_prefix, parent_id: parent_id,
                      editable: editable, edit_on_modal: false,
                      deletable: deletable})
  end

  def save_agent(params)
    agent = LinkedData::Client::Models::Agent.new(values: params)
    agent.creator = session[:user].id
    agent.save
  end

  def update_agent(id = params[:id], params)
    agent = LinkedData::Client::Models::Agent.find(id)

    params[:creator] = session[:user].id if (agent.creator.nil? || agent.creator.empty?) && (params[:creator] || '').empty?

    res = agent.update(values: params)
    [res, agent.update_from_params(params)]
  end

  def update_agent_usages_action(agent, params)
    current_usages = helpers.agents_used_properties(agent)
    new_usages = params

    diffs = current_usages.keys.each_with_object({}) do |key, result|
      removed_values = current_usages[key] - Array(new_usages[key])
      added_values = Array(new_usages[key]) - current_usages[key]
      result[key] =  removed_values +  added_values
    end

    # changed_usages = new_usages.empty? ? current_usages :  new_usages.select { |x, v| !((current_usages[x] - v) + (v - current_usages[x])).empty? }


    changed_usages = diffs.reduce({}) do |h, attr_acronyms|
      attr, acronyms = attr_acronyms
      acronyms.each do |acronym|
        h[acronym] ||= []
        h[acronym] << attr
      end
      h
    end
    responses = {}
    changed_usages.each do |ontology, attrs|
      ontology = LinkedData::Client::Models::Ontology.find_by_acronym(ontology).first
      sub = ontology.explore.latest_submission({ include: attrs.join(',') })
      values = {}
      attrs.each do |attr|
        current_val = sub.send(attr)
        if current_val.is_a?(Array)
          existent_agent = current_val.find_index { |x| x.id.eql?(agent.id) }
          if existent_agent
            current_val.delete_at(existent_agent)
          else
            current_val << agent
          end
          values[attr.to_sym] = current_val.map { |x| x.id }
        else
          values[attr.to_sym] = agent.id
        end
      end

      responses[ontology] = sub.update(values: values, cache_refresh_all: false)
    end

    [responses, new_usages]
  end

  def agent_usages_params
    p = params.permit(hasCreator: [], hasContributor: [], curatedBy: [], publisher: [], fundedBy: [], endorsedBy: [], translator: [])
    p.to_h
  end

  def agent_params
    p = params.permit(:agentType, :name, :email, :acronym, :homepage, :creator,
                      { identifiers: [:notation, :schemaAgency, :creator] },
                      { affiliations: [:id, :agentType, :name, :homepage, :acronym, :creator, { identifiers: [:notation, :schemaAgency, :creator] }] }
    )
    p = p.to_h
    p.transform_values do |v|
      if v.is_a? Hash
        v.values.reject(&:empty?)
      elsif v.is_a? Array
        v.reject(&:empty?)
      else
        v
      end
    end
    p[:identifiers] = p[:identifiers].reject{ |key, value| value["notation"].empty? }
    identifiers_schemaAgency = params[:agentType].eql?('person') ? 'ORCID' : 'ROR'
    p[:identifiers]&.each_value do |identifier|
      identifier[:schemaAgency] = identifiers_schemaAgency
      if identifier[:schemaAgency].downcase.eql?('orcid')
        identifier[:notation] = normalize_orcid(identifier[:notation])
      else
        identifier[:notation] = normalize_ror(identifier[:notation])
      end
    end

    p[:identifiers] = (p[:identifiers] || {}).values
    p[:affiliations] = (p[:affiliations] || {}).values
    p[:affiliations].each do |affiliation|
      affiliation[:identifiers] = affiliation[:identifiers].values if affiliation.is_a?(Hash) && affiliation[:identifiers]
    end
    p
  end

  def normalize_orcid(orcid)
    case orcid
    when /\A\d{16}\z/
      # Case 1: 16 digits, add dashes
      orcid = orcid.scan(/.{1,4}/).join('-')

    when /\A\d{4}-\d{4}-\d{4}-\d{4}\z/
      orcid = orcid

    when /\Ahttps:\/\/(www\.)?orcid\.org\/\d{4}-\d{4}-\d{4}-\d{4}\z/
      # Case 3: ORCID URL (with or without "www."), extract the numbers with dashes
      orcid = orcid.split('/').last

    when /\Aorcid\.org\/\d{4}-\d{4}-\d{4}-\d{4}\z/
      # Case 4: ORCID without scheme (http/https)
      orcid = orcid.split('/').last

    when /\Awww\.orcid\.org\/\d{4}-\d{4}-\d{4}-\d{4}\z/
      # Case 5: ORCID with "www." without scheme
      orcid = orcid.split('/').last
    end

    return orcid
  end

  def normalize_ror(ror)
    case ror
    when /\A0\w{6}\d{2}\z/
      # Case 1: 9 characters, starting with '0', 6 alphanumeric, ending with 2 digits
      ror = ror

    when /\Ahttps:\/\/ror\.org\/(0\w{6}\d{2})\z/
      # Case 2: Full URL with 'https://ror.org/', extract the ROR ID
      ror = ror.split('/').last

    when /\Aror\.org\/(0\w{6}\d{2})\z/
      # Case 3: ROR without scheme (http/https), extract the ROR ID
      ror = ror.split('/').last
    end

    return ror
  end

  def generate_errors(response_errors)
    errors = []
    response_errors.values.each_with_index do |v, i|
      if v[:existence]
        errors << "#{response_errors.keys[i].capitalize} #{t('agents.errors.required')}"
      elsif v[:unique_identifiers]
        errors << t('agents.errors.used_identifier')
      elsif v[:no_url]
        errors << t('agents.errors.invalid_url')
      else
        errors << JSON.pretty_generate(response_errors)
      end
    end
    return errors
  end

  def check_agents_enabled
    unless helpers.agents_enabled? || current_user_admin?
      redirect_to root_path, alert: 'Agents endpoint is not available'
    end
  end
end

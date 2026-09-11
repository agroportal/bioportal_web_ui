class Admin::AgentsController < ApplicationController
  layout :determine_layout
  before_action :authorize_admin

  def index  
  options = {  
    include: 'agentType,name,homepage,acronym,email,identifiers,affiliations,usages,created,creator'
  }  
  @agents = LinkedData::Client::Models::Agent.all(options)
  # Forwarded by the admin tabs from /admin?section=agents&page=14.
  @page = params[:page].to_i
  end
end
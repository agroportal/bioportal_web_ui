# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SubmissionFilter do
  # Minimal host: the concern only needs number formatting and a few
  # controller-level helpers to build its ontology hashes.
  let(:host_class) do
    Class.new do
      include ActionView::Helpers::NumberHelper
      include SubmissionFilter
    end
  end

  let(:host) { host_class.new }

  # An out-of-enum value really stored on AgroPortal (BEVON): the API only
  # enforces the presence of `status`, not its membership of the enum.
  let(:unknown_status) { 'http://purl.org/adms/status/UnderDevelopment' }

  def ontology_double(acronym)
    OpenStruct.new(id: "http://example.org/ontologies/#{acronym}", acronym: acronym,
                   name: acronym, viewOf: nil, group: [], hasDomain: [],
                   administeredBy: [], projects: [], notes: [],
                   viewingRestriction: 'public')
  end

  def submission_double(ontology, status)
    OpenStruct.new(ontology: { id: ontology.id }, status: status, description: '',
                   submissionStatus: [], deprecated: false, contact: nil, metrics: nil,
                   pullLocation: nil, creationDate: nil, released: nil,
                   naturalLanguage: [], hasFormalityLevel: nil, isOfType: nil,
                   hasOntologyLanguage: 'OWL')
  end

  # One ontology per interesting status, plus one with no READY submission at all
  # (parsing failed), which is what makes its status nil for anonymous visitors.
  let(:ontologies) { %w[PROD RETIRED UNKNOWN NOSUB].map { |a| ontology_double(a) } }

  let(:submissions) do
    prod, retired, unknown, = ontologies
    [submission_double(prod, 'production'),
     submission_double(retired, 'retired'),
     submission_double(unknown, unknown_status)]
  end

  def browse(params)
    request_params = host.send(:filters_params, ActionController::Parameters.new(params))

    host.send(:filter_submissions, ontologies,
              query: nil, retired: request_params[:retired], show_views: false,
              private_only: false, languages: nil, page_size: 10,
              formality_level: nil, is_of_type: nil, groups: nil,
              categories: nil, formats: nil).map { |s| s[:acronym] }
  end

  before do
    allow(host).to receive(:current_user_admin?).and_return(false)
    allow(host).to receive(:submission_status2string).and_return('')
    allow(LinkedData::Client::Models::OntologySubmission).to receive(:all).and_return(submissions)
    host.instance_variable_set(:@analytics, {})
  end

  describe 'default browse' do
    it 'hides retired ontologies' do
      expect(browse({})).not_to include('RETIRED')
    end

    it 'keeps ontologies whose submission has no status' do
      expect(browse({})).to include('NOSUB')
    end

    it 'keeps ontologies whose status is outside the enum' do
      expect(browse({})).to include('UNKNOWN')
    end
  end

  describe 'retired filter' do
    it 'shows retired ontologies alone' do
      expect(browse(show_retired: 'true')).to eq(['RETIRED'])
    end
  end
end

# frozen_string_literal: true

require "rails_helper"

RSpec.describe ConceptDetailsComponent, type: :component do
  let(:concept) { "http://opendata.inrae.fr/thesaurusINRAE/c_10180" }

  def component(reified_keys: [], lang: "all")
    described_class.new(id: "concept-details", acronym: "INRAETHES", concept_id: concept,
                        reified_keys: reified_keys, lang: lang)
  end

  # Every row of the Raw block asks the ontology what its property is called,
  # once a day - so each example starts from an empty cache. The rows read below
  # carry no name of their own.
  before do
    Rails.cache.clear
    allow(LinkedData::Client::HTTP).to receive(:get).and_return(OpenStruct.new(label: nil))
  end

  # The raw side of the Definitions row holds the same nodes, and is read the
  # same way - but only the rows the caller names, because every other row is
  # full of URIs that are classes and have to stay links.
  describe "#reified_row?" do
    let(:rows) { component(reified_keys: %w[definition]) }

    it "holds for the row the caller named" do
      expect(rows.reified_row?("http://www.w3.org/2004/02/skos/core#definition")).to be true
    end

    it "does not hold for a row of class URIs" do
      %w[
        http://www.w3.org/2004/02/skos/core#broader
        http://www.w3.org/2004/02/skos/core#narrower
        http://www.w3.org/2004/02/skos/core#inScheme
        http://www.w3.org/1999/02/22-rdf-syntax-ns#type
        http://purl.org/dc/terms/description
      ].each do |predicate|
        expect(rows.reified_row?(predicate)).to be false
      end
    end

    # Schemes, collections, and the node modal itself render through this
    # component too, and none of them names a row: they keep their chips.
    it "holds for nothing when no row is named" do
      expect(component.reified_row?("http://www.w3.org/2004/02/skos/core#definition")).to be false
    end
  end

  # Under "all languages" the `definition` attribute holds only the literals -
  # the API groups them by language, and a node URI has none - so the Definitions
  # row reads the raw triples instead, and both rows say the same thing.
  describe "#reified_values" do
    let(:node) { "http://opendata.inrae.fr/thesaurusINRAE/note_101800en" }
    let(:definition_property) { "http://www.w3.org/2004/02/skos/core#definition" }

    def with_row(predicate, values, reified_keys: %w[definition])
      described_class.new(id: "concept-details", acronym: "INRAETHES", concept_id: concept,
                          reified_keys: reified_keys, lang: "all",
                          properties: OpenStruct.new(predicate => values))
    end

    it "is the raw row when it holds a node the attribute would have dropped" do
      values = { "@none" => [node], "en" => ["A parasitic disease."] }

      expect(with_row(definition_property, values).reified_values).to eq(values)
    end

    it "is the raw row when the node is one of a plain list" do
      expect(with_row(definition_property, [node, "A parasitic disease."]).reified_values)
        .to eq([node, "A parasitic disease."])
    end

    # Which property counts as the definition is the API's to say; only a node
    # makes it worth reading the triples instead of the attribute.
    it "is nil when the row holds only literals" do
      expect(with_row(definition_property, ["A parasitic disease."]).reified_values).to be_nil
      expect(with_row(definition_property, { "en" => ["A parasitic disease."] }).reified_values).to be_nil
    end

    it "is nil when no row was named" do
      expect(with_row(definition_property, [node], reified_keys: []).reified_values).to be_nil
    end

    it "is nil when no row matches the ones named" do
      expect(with_row("http://www.w3.org/2004/02/skos/core#broader", [node]).reified_values).to be_nil
    end
  end

  describe "#definitions_component" do
    subject(:definitions) do
      component(reified_keys: %w[definition], lang: "fr")
        .definitions_component(["A parasitic disease."], "http://www.w3.org/2004/02/skos/core#definition",
                               "INRAETHES")
    end

    it "reads the row the way the Definitions row reads it" do
      expect(definitions).to be_a(DefinitionsComponent)
      expect(render_inline(definitions).css(".definition-text").first.text.strip)
        .to eq("A parasitic disease.")
    end

    it "resolves the row's nodes against this resource, in the language of the page" do
      expect(definitions.instance_variable_get(:@acronym)).to eq("INRAETHES")
      expect(definitions.instance_variable_get(:@parent_uri)).to eq(concept)
      expect(definitions.instance_variable_get(:@lang)).to eq("fr")
    end

    it "names the row after its predicate" do
      expect(definitions.instance_variable_get(:@id)).to eq("raw-definition")
    end
  end

  # A raw row is named as BioPortal names it: the property's label in the
  # ontology - "definition", not "obo_purl:IAO_0000115" - and failing that the
  # URI's last segment, with no prefix in front of it.
  describe "row names" do
    let(:definition_property) { "http://purl.obolibrary.org/obo/IAO_0000115" }
    let(:synonym_property) { "http://www.geneontology.org/formats/oboInOwl#hasExactSynonym" }

    def row_name(property = definition_property)
      rendered = render_inline(
        described_class.new(id: "concept-details", acronym: "PO", concept_id: concept, bottom_keys: %w[subClassOf],
                            properties: OpenStruct.new(property => ["An anatomical entity."]))
      )
      rendered.css("th").first.text.strip
    end

    it "is the property's label in the ontology the resource belongs to" do
      expect(LinkedData::Client::HTTP).to receive(:get)
        .with("/ontologies/PO/properties/#{CGI.escape(definition_property)}/label")
        .and_return(OpenStruct.new(label: "definition"))

      expect(row_name).to eq("definition")
    end

    # A property an imported vocabulary defines is labelled nowhere in this
    # submission, and the URI's last segment is then all there is to read.
    it "is the URI's last segment when the ontology labels the property nowhere" do
      expect(row_name).to eq("IAO_0000115")
      expect(row_name(synonym_property)).to eq("hasExactSynonym")
    end

    it "is the URI's last segment when the lookup fails" do
      allow(LinkedData::Client::HTTP).to receive(:get).and_raise(StandardError)

      expect(row_name).to eq("IAO_0000115")
    end
  end
end

# frozen_string_literal: true

require 'rails_helper'

RSpec.describe TableComponent, type: :component do
  def container(page:)
    render_inline(described_class.new(id: 'agents-table', paging: true, page: page))
      .css('.table-component-container')
      .first
  end

  it 'exposes the requested page so the table opens on it' do
    expect(container(page: 14)['data-table-component-page-value']).to eq('14')
  end

  it 'falls back to the first page when the param is missing or junk' do
    expect(container(page: 0)['data-table-component-page-value']).to eq('1')
    expect(container(page: 'abc')['data-table-component-page-value']).to eq('1')
  end

  it 'stays URL agnostic when no page is given' do
    expect(container(page: nil).attributes).not_to have_key('data-table-component-page-value')
  end
end

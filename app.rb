# -*- coding: utf-8 -*-
require 'sinatra'
require 'haml'
Dir["lib/*.rb"].each { |file| require_relative file }

helpers do
  include RenderingConcerns, APIData, QueryParams

  def page(funder, results, total_results)
    funder_info = { nesting: funder['hierarchy'],
                    nesting_names: funder['hierarchy-names'],
                    id: funder['id'] }
    { funder: funder_info,
      bare_query: funder['name'],
      query: funder['name'],
      page: query_page,
      items: results,
      paginate: Paginate.new(query_page, query_rows, total_results),
      facets: ['category', 'type', 'year', 'publication', 'publisher', 'source'] }
  end
end

get '/' do
  if params.has_key?('q')
    funder = funder_hash(params['q'])
    works = funder_works_hash(params['q'], params)
    results = SearchResult.results_from_items(works['items'], funder['hierarchy-names'])

    if params['format'] == 'csv'
      content_type 'text/csv'
      SearchResult.generate_csv(results)
    else
      haml :results, locals: { page: page(funder, results, works['total-results']) }
    end
  else
    haml :splash, locals: { page: {} }
  end
end

# Keep this. Handy feature that already uses public APIs. Requires no modification.
require 'faraday'
require 'faraday_middleware'

configure do
  # Set up for http requests to data.crossref.org and dx.doi.org
  dx_doi_org = Faraday.new(url: 'http://dx.doi.org') do |c|
    c.use FaradayMiddleware::FollowRedirects, limit: 5
    c.adapter :net_http
  end

  set :data_service, Faraday.new(url: 'http://data.crossref.org')
  set :dx_doi_org, dx_doi_org

  # Citation format types
  set :citation_formats, {
    'bibtex' => 'application/x-bibtex',
    'ris' => 'application/x-research-info-systems',
    'apa' => 'text/x-bibliography; style=apa',
    'harvard' => 'text/x-bibliography; style=harvard3',
    'ieee' => 'text/x-bibliography; style=ieee',
    'mla' => 'text/x-bibliography; style=mla',
    'vancouver' => 'text/x-bibliography; style=vancouver',
    'chicago' => 'text/x-bibliography; style=chicago-fullnote-bibliography'
  }
end

get '/citation' do
  citation_format = settings.citation_formats[params[:format]]

  res = settings.data_service.get do |req|
    req.url "/#{params[:doi]}"
    req.headers['Accept'] = citation_format
  end

  content_type citation_format
  res.body if res.success?
end

# -*- coding: utf-8 -*-
require 'sinatra'
require 'json'
require 'rsolr'
require 'mongo'
require 'haml'
require 'will_paginate'
require 'cgi'
require 'faraday'
require 'faraday_middleware'
require 'haml'
require 'rack-session-mongo'
# require 'oauth2'
# require 'omniauth-orcid'
require 'resque'
require 'open-uri'
require 'uri'
require 'csv'
require 'parallel'
require 'pry'
require_relative 'lib/paginate'
require_relative 'lib/result'
require_relative 'lib/bootstrap'
require_relative 'lib/doi'
require_relative 'lib/orcid'
require_relative 'lib/session'
require_relative 'lib/data'
require_relative 'lib/orcid_update'
require_relative 'lib/orcid_claim'
require_relative 'lib/orcid_auth'
require_relative 'lib/api_calls'
MIN_MATCH_SCORE = 75
MIN_MATCH_TERMS = 3
MAX_MATCH_TEXTS = 1000

after do
  response.headers['Access-Control-Allow-Origin'] = '*'
end

configure do
  config = JSON.parse(File.open('conf/app.json').read)
  config.each_pair do |key, value|
    set key.to_sym, value
  end

  # Work around rack protection referrer bug
  set :protection, :except => :json_csrf
  set :app_file, __FILE__
  # Configure solr
  set :api_url, ENV["API_URL"]
  set :solr, settings.api_url
  # Configure mongo
  set :mongo, Mongo::Connection.new(ENV["MONGO_HOST"])
  set :dois, settings.mongo[settings.mongo_db]['dois']
  set :shorts, settings.mongo[settings.mongo_db]['shorts']
  set :issns, settings.mongo[settings.mongo_db]['issns']
  set :citations, settings.mongo[settings.mongo_db]['citations']
  set :patents, settings.mongo[settings.mongo_db]['patents']
  set :claims, settings.mongo[settings.mongo_db]['claims']
  set :orcids, settings.mongo[settings.mongo_db]['orcids']
  set :links, settings.mongo[settings.mongo_db]['links']
  set :funders, settings.mongo[settings.mongo_db]['funders']
  set :orcid_client_id, ENV["ORCID_CLIENT_ID"]
  set :orcid_client_secret, ENV["ORCID_CLIENT_SECRET"]
  set :orcid_import_callback, ENV["ORCID_IMPORT_CALLBACK"]
  set :orcid_redirect_uri, ENV["ORCID_REDIRECT_URI"]

  # Set up for http requests to data.crossref.org and dx.doi.org
  doi_org = Faraday.new(:url => 'https://doi.org') do |c|
    c.use FaradayMiddleware::FollowRedirects, :limit => 5
    c.adapter :net_http
  end

  set :data_service, Faraday.new(:url => 'https://data.crossref.org')
  set :doi_org, doi_org

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

  # Set facet fields

  set :facet_fields, {"type-name" => "type","published" => "year","container-title" => "publication","publisher-name" => "publisher","funder-name" => "funder name"}
  set :crmds_facet_fields, {"type-name" => "type","published" => "year","container-title" => "publication","publisher-name" => "publisher","funder-name" => "funder name"}
  set :fundref_facet_fields, {"type-name" => "type","published" => "year","container-title" => "publication","publisher-name" => "publisher","funder-name" => "funder name"}
  set :chorus_facet_fields, {"type-name" => "type","published" => "year","container-title" => "publication","publisher-name" => "publisher","funder-name" => "funder name"}

  # Orcid endpoint
  set :orcid_service, Faraday.new(:url => settings.orcid_site)

  # Orcid oauth2 object we can use to make API calls
  set :orcid_oauth, OAuth2::Client.new(settings.orcid_client_id,
    settings.orcid_client_secret,
    {:site => settings.orcid_site})

    # Set up session and auth middlewares for ORCiD sign in
    use Rack::Session::Mongo, settings.mongo[settings.mongo_db]

    # use OmniAuth::Builder do
    #   provider :orcid, settings.orcid_client_id, settings.orcid_client_secret, {:member => true, :redirect_uri => settings.orcid_redirect_uri}
    # end

    use OmniAuth::Builder do
      provider :orcid, settings.orcid_client_id, settings.orcid_client_secret, :client_options => {
        :site => settings.orcid_site,
        :redirect_uri => settings.orcid_redirect_uri,
        :authorize_url => settings.orcid_authorize_url,
        :token_url => settings.orcid_token_url,
        :scope => '/read-limited /activities/update'
      }
    end

    # Branding options
    set :crmds_branding, {
      :logo_path => '//assets.crossref.org/logo/crossref-logo-landscape-200.png',
      :logo_small_path => '//assets.crossref.org/logo/crossref-logo-landscape-100.png',
      :logo_link => '/',
      :search_placeholder => 'Title, author, DOI, ORCID iD, etc.',
      :search_action => '/',
      :search_typeahead => false,
      :examples_layout => :crmds_help_list,
      :header_links_profile => :crmds,
      :facet_fields => settings.crmds_facet_fields,
      :downloads => [],
      :show_doaj_label => true,
      :show_profile_link => true
    }

    set :fundref_branding, {
      :logo_path => '//assets.crossref.org/logo/crossref-logo-landscape-200.png',
      :logo_small_path => '//assets.crossref.org/logo/crossref-logo-landscape-100.png',
      :logo_link => '/funding',
      :search_placeholder => 'Search funders...',
      :search_action => '/funding',
      :search_typeahead => :funder_name,
      :examples_layout => :fundref_help_list,
      :header_links_profile => :fundref,
      :facet_fields => settings.fundref_facet_fields,
      :downloads => [:fundref_csv],
      :show_doaj_label => true,
      :show_profile_link => true
    }

    set :chorus_branding, {
      :logo_path => '/chorus-logo.png',
      :logo_link => '/chorus',
      :search_placeholder => 'Funder name',
      :search_action => '/chorus',
      :search_typeahead => :funder_name,
      :examples_layout => :fundref_help_list,
      :header_links_profile => :chorus,
      :footer_links_profile => :chorus,
      :facet_fields => settings.chorus_facet_fields,
      :downloads => [:fundref_csv],
      :show_doaj_label => false,
      :show_profile_link => false,
      :filter_prefixes => ['10.1103', '10.1021', '10.1063', '10.1016',
        '10.1093', '10.1109', '10.1002', '10.1126']
      }

      set :test_prefixes, ["10.5555", "10.55555"]
    end

    helpers do
      include Doi
      include Orcid
      include Session

      def partial template, locals
        haml template.to_sym, :layout => false, :locals => locals
      end

      def citations doi
        doi = to_doi(doi)
        citations = settings.citations.find({'to.id' => doi})

        citations.map do |citation|
          hsh = {
            :id => citation['from']['id'],
            :authority => citation['from']['authority'],
            :type => citation['from']['type'],
          }

          if citation['from']['authority'] == 'cambia'
            patent = settings.patents.find_one({:patent_key => citation['from']['id']})
            hsh[:url] = "https://lens.org/lens/patent/#{patent['pub_key']}"
            hsh[:title] = patent['title']
          end

          hsh
        end
      end

      def check_params
        api_url = settings.api_url
        api_token = ENV["CROSSREF_API_TOKEN"].nil? ? nil : ENV["CROSSREF_API_TOKEN"]
        if params.has_key?("base_uri") && not(params["base_uri"].nil?)
          # remove trailing slash
          standardized_url = params["base_uri"] =~ /.*\/$/ ? params["base_uri"].chop : params["base_uri"]
          api_url = standardized_url
          api_token = nil
        end
        @api = APICalls.new(api_url,api_token)
      end

      def select query_params

        page = [query_page, 10].min
        rows = query_rows
        query_params.merge!(:page => page)
        results = @api.query(query_params)
      end

      def select_all query_params

        query_params[:rows] = 1000
        results = @api.query(query_params)
      end

      def response_format
        if params.has_key?('format') && params['format'] == 'json'
          'json'
        else
          'html'
        end
      end

      def query_page
        if params.has_key? 'page'
          params['page'].to_i
        else
          1
        end
      end

      def query_rows
        if params.has_key? 'rows'
          params['rows'].to_i
        else
          settings.default_rows
        end
      end

      def query_columns
        ['*', 'score']
      end

      def query_terms
        query_info = query_type
        case query_info[:type]
        when :doi
          "doi:#{query_info[:value]}"
        when :short_doi
          "doi:#{query_info[:value]}"
        when :issn
          "issn:#{query_info[:value]}"
        when :orcid
          "orcid:#{query_info[:value]}"
        else
          scrub_query(params['q'], false)
        end
      end

      def query_type
        if doi? params['q']
          {:type => :doi, :value => to_doi(params['q']).downcase}
        elsif short_doi?(params['q']) || very_short_doi?(params['q'])
          {:type => :short_doi, :value => to_long_doi(params['q'])}
        elsif issn? params['q']
          {:type => :issn, :value => params['q'].strip.upcase}
        elsif orcid? params['q']
          {:type => :orcid, :value => params['q'].strip}
        else
          {:type => :normal}
        end
      end

      def abstract_facet_query
        fq = {}
        settings.facet_fields.keys.each do |field|
          if params.has_key? field
            val = params[field]
            params[field].split(';').each do |val|
              fq[field] ||= []
              fq[field] << val
            end
          end
        end
        fq
      end

      def facet_query
        fq = []
        abstract_facet_query.each_pair do |name, values|
          values.each do |value|
            fq << "#{name}:#{value}"
          end
        end
        fq
      end

      def sort_term
        if 'year' == params['sort']
          'published&order=desc'
        else
          'score&order=desc'
        end
      end

      def base_query
        {
          :sort => sort_term,
          :rows => query_rows,
          :facet => settings.facet_fields.keys,
        }
      end

      def fundref_query
        query = base_query.merge({:q => "funder_doi:\"#{query_terms}\""})
        fq = facet_query
        query['fq'] = fq unless fq.empty?
        query
      end

      def search_query
        terms = query_terms || '*:*'
        chk_query = process_search_query terms
        query = chk_query.empty? ? base_query.merge({:q => terms}) : base_query.merge(chk_query)
        fq = facet_query
        if query.key?(:filter_query)
          query[:filter_query] += fq unless fq.empty?
        else
          query[:filter_query] = fq unless fq.empty?
        end
        query
      end

      def process_search_query terms
        query = {}
        case terms
        when /^orcid\:/,/^doi\:/
          query[:filter_query] = [terms]
        end
        query
      end
      def fundref_doi_query funder_dois, prefixes=nil
        doi_q = funder_dois.map {|doi| "funder:#{doi}" }
        query = {}
        query[:filter_query] = doi_q
        query = base_query.merge(query)

        if prefixes
          prefixes = prefixes.map {|prefix| "http://id.crossref.org/prefix/#{prefix}"}
          prefix_q = prefixes.map {|prefix| "owner_prefix:\"#{prefix}\""}.join(' OR ')
          query[:q] = "(#{query[:q]}) AND (#{prefix_q})"
        end
        fq = facet_query
        query[:filter_query] += fq unless fq.empty?
        query
      end

      def result_page solr_result
        {
          :bare_sort => params['sort'],
          :bare_query => params['q'],
          :query_type => query_type,
          :query => query_terms,
          :facet_query => abstract_facet_query,
          :page => query_page,
          :rows => {
            :options => settings.typical_rows,
            :actual => query_rows
          },
          :items => search_results(solr_result),
          :paginate => Paginate.new(query_page, query_rows, solr_result),
          :facets => solr_result['message']['facets']
        }
      end

      def facet_link_not field_name, field_value
        fq = abstract_facet_query
        fq[field_name].delete field_value
        fq.delete(field_name) if fq[field_name].empty?

        link = "#{request.path_info}?q=#{CGI.escape(params['q'])}"
        link += "&base_uri=#{params['base_uri']}" if params.key?("base_uri")
        fq.each_pair do |field, vals|
          link += "&#{field}=#{CGI.escape(vals.join(';'))}"
        end
        link
      end

      def facet_link field_name, field_value
        fq = abstract_facet_query
        fq[field_name] ||= []
        fq[field_name] << field_value

        link = "#{request.path_info}?q=#{CGI.escape(params['q'])}"
        link += "&base_uri=#{params['base_uri']}" if params.key?("base_uri")
        fq.each_pair do |field, vals|
          link += "&#{field}=#{CGI.escape(vals.join(';'))}"
        end
        link
      end

      def fundref_csv_link id
        "/funding.csv?q=#{id}&format=csv"
      end

      def facet? field_name
        abstract_facet_query.has_key? field_name
      end

      def search_link opts
        fields = settings.facet_fields.keys + ['q', 'sort']
        parts = fields.map do |field|
          if opts.has_key? field.to_sym
            "#{field}=#{CGI.escape(opts[field.to_sym])}"
          elsif params.has_key? field
            params[field].split(';').map do |field_value|
              "#{field}=#{CGI.escape(params[field])}"
            end
          end
        end

        "#{request.path_info}?#{parts.compact.flatten.join('&')}"
      end

      def authors_text contributors
        authors = contributors.map do |c|
          "#{c['given_name']} #{c['surname']}"
        end
        authors.join ', '
      end

      def search_results solr_result, oauth = nil
        claimed_dois = []
        profile_dois = []

        if signed_in?
          orcid_record = settings.orcids.find_one({:orcid => sign_in_id})
          unless orcid_record.nil?
            claimed_dois = orcid_record['dois'] + orcid_record['locked_dois'] if orcid_record
            profile_dois = orcid_record['dois']
          end
        end
        solr_result['message']['items'].map do |solr_doc|
          doi = solr_doc['DOI']
          plain_doi = to_doi(doi)
          in_profile = profile_dois.include?(plain_doi)
          claimed = claimed_dois.include?(plain_doi)
          user_state = {
            :in_profile => in_profile,
            :claimed => claimed
          }
          SearchResult.new solr_doc, solr_result, citations(solr_doc['DOI']), user_state
        end
      end

      def result_publication_date record
        published = record["published-print"] || record["published-online"]
        published = published["date-parts"].join("-")
        #year = record[""]
        #year = record['hl_year'].to_i
        #month = record['month'] || 1
        #day = record['day'] || 1
        published
      end

      def scrub_query query_str, remove_short_operators
        query_str = query_str.gsub(/[~{}*\"\.\[\]\(\)\-:;\/%^&]/, ' ')
        query_str = query_str.gsub(/[\+\!\-]/, ' ') if remove_short_operators
        query_str = query_str.gsub(/AND/, ' ')
        query_str = query_str.gsub(/OR/, ' ')
        query_str.gsub(/NOT/, ' ')

        if query_str.gsub(/[\+\!\-]/,'').strip.empty?
          nil
        else
          query_str
        end
      end

      def render_top_funder_name m, names
        top_funder_id = m.keys.first
        names[top_funder_id]
      end

      def render_top_funder_id m
        m.keys.first
      end

      def rest_funder_nesting m
        m[m.keys.first]
      end

      def render_funders m, names, indent, &block
        ks = m.keys
        ks.each do |k|
          if m[k].keys == ['more']
            block.call(indent + 1, k, names[k], true)
          else
            block.call(indent + 1, k, names[k], false)
            render_funders(m[k], names, indent + 1, &block)
          end
        end
      end

      def render_funders_full_children indent, current_id, children_map, names, &block
        block.call(indent, current_id, names[current_id])

        if !children_map[current_id].nil?
          children_map[current_id].each do |c|
            render_funders_full_children(indent + 1, c[:id], children_map, names, &block)
          end
        end
      end

      def render_funders_full id, indent, &block
        funder = settings.funders.find_one({:id => id})
        names = funder['descendant_names']
        names[id] = funder['primary_name_display']

        descendants = funder['descendants'].map do |d_id|
          d = settings.funders.find_one({:id => d_id})
          {:id => d_id, :parent => d['parent']}
        end

        children = descendants.reduce({}) do |memo, d|
          memo[d[:parent]] ||= []
          memo[d[:parent]] << d
          memo
        end

        render_funders_full_children(indent, id, children, names, &block)
      end

      def funder_doi_from_id id
        query = @api.get_funder_info(id)
        dois = []
        funder_hsh = {}
        if query["message"]
          query = query["message"]
          funder_hsh[:id] = query["id"]
          funder_hsh[:primary_name_display] = query["name"]
          dois = [funder_hsh[:id]]
          dois << query["descendants"] if query.key?("descendants")
          dois.flatten! if dois.count > 1
          funder_hsh[:nesting] = query['hierarchy']
          funder_hsh[:nesting_names] = query['hierarchy-names']
        end
        [dois,funder_hsh]
      end

      def test_doi? doi
        plain_doi = to_doi(doi)
        plain_doi.start_with?('10.5555') || plain_doi.start_with?('10.55555')
      end

      def funder_count
        @api.count("funders")
      end

      def get_all_results(qp)
        @api.call("/funders/#{params['q']}/works",qp)
      end

      def iterate_results(total_pages,qp,results = [])
        page = qp[:page].to_i
        if page <= total_pages
          sr = get_all_results(qp)
          results << search_results(sr)
          qp[:page] = page + 1
          qp.delete(:offset)
          iterate_results(total_pages,qp,results)
        else
          results.flatten!
        end
      end

      def splash_stats
        doi_num = @api.count("works")
        funders = @api.count("funders")
        funding_dois = @api.count("works","has-funder:true")
        {:dois => doi_num,
          :funding_dois => funding_dois,
          :funders => funders}
        end

      end

      before do
        check_params
        set_after_signin_redirect(request.fullpath)
      end

      helpers do
        def handle_fundref branding
          prefixes = branding[:filter_prefixes]

          if !params.has_key?('q')
            haml :splash, :locals => {:page => {:stats => splash_stats, :branding => branding}}
          elsif params.has_key?('format') && params['format'] == 'csv'
            all_results = []
            rest = []
            qp = {:rows => 1000}
            solr_result= @api.call("/funders/#{params['q']}/works",qp)
            tr =  solr_result["message"]["total-results"].to_i
            rows = solr_result["message"]["items-per-page"].to_i
            results = search_results(solr_result)
            if rows < tr
              tp = (tr/rows).ceil
              rem = tr % rows
              tp += 1 if rem != 0
              qp[:page] = 2
              rest = iterate_results(tp,qp)
            end
            all_results = rest.count == 0 ? results : results + rest
            csv_response = CSV.generate do |csv|
              csv << ['DOI', 'Type', 'Year', 'Title', 'Publication', 'Authors', 'Funders', 'Awards']
              all_results.each do |result|
                csv << [result.display_doi,
                  result.type,
                  result.coins_year,
                  result.coins_atitle,
                  result.coins_title,
                  result.coins_authors,
                  result.plain_funder_names.join(","),
                  result.award_numbers
                ]
              end
            end

            content_type 'text/csv'
            csv_response
          else
            funder_info = {}
            id = params['q']
            funder_dois,funder = funder_doi_from_id(params['q'])
            solr_result = select(fundref_doi_query(funder_dois))
            page = result_page(solr_result)
            page[:bare_query] = funder[:primary_name_display]
            page[:query] = scrub_query(page[:bare_query], false)
            haml :results, :locals => {
              :page => {
                :branding => branding,
                :funder => funder
              }.merge(page)
            }
          end
        end

        def resolve_references citation_texts
          page = {}
          begin
            if citation_texts.count > MAX_MATCH_TEXTS
              page = {
                :results => [],
                :query_ok => false,
                :reason => "Too many citations. Maximum is #{MAX_MATCH_TEXTS}"
              }
            else
              results = Parallel.map(citation_texts.take(MAX_MATCH_TEXTS),
              :in_processes => settings.links_process_count) do |citation_text|
                terms = scrub_query(citation_text, true)
                if terms.strip.empty?
                  {
                    :text => citation_text,
                    :reason => 'Citation text contains no characters or digits',
                    :match => false
                  }
                else
                  params = base_query.merge({:q => terms, :rows => 1})
                  result = @api.query(params)
                  match = result['message']['items'].first
                  # processing doi url to match with Crossref doi display guideline
                  match['URL'].sub!("http://dx.","https://")
                  if citation_text.split.count < MIN_MATCH_TERMS
                    {
                      :text => citation_text,
                      :reason => 'Too few terms',
                      :match => false
                    }
                  elsif match['score'].to_f < MIN_MATCH_SCORE
                    {
                      :text => citation_text,
                      :reason => 'Result score too low',
                      :match => false
                    }
                  else
                    {
                      :text => citation_text,
                      :match => true,
                      :doi => match['URL'],
                      :coins => search_results(result).first.coins,
                      :score => match['score'].to_f
                    }
                  end
                end
              end

              page = {
                :results => results,
                :query_ok => true
              }
            end
          rescue JSON::ParserError => e
            page = {
              :results => [],
              :query_ok => false,
              :reason => 'Request contained malformed JSON'
            }
          rescue Exception => e
            page = {
              :results => [],
              :query_ok => false,
              :reason => e.message,
              :trace => e.backtrace
            }
          end

          page
        end
      end

      get '/fundref' do
        url_params = []
        url_params << "q=#{URI.encode_www_form_component(params[:q])}" if params[:q]
        url_params << "sort=#{URI.encode_www_form_component(params[:sort])}" if params[:sort]
        url_params << "format=#{URI.encode_www_form_component(params[:format])}" if params[:format]

        url = '/funding'
        url += "?#{url_params.join('&')}" if not url_params.empty?
        redirect url
      end

      get '/fundref.csv' do
        url_params = []
        url_params << "q=#{URI.encode_www_form_component(params[:q])}" if params[:q]
        url_params << "sort=#{URI.encode_www_form_component(params[:sort])}" if params[:sort]
        url_params << "format=#{URI.encode_www_form_component(params[:format])}" if params[:format]

        url = '/funding.csv'
        url += "?#{url_params.join('&')}" if not url_params.empty?
        redirect url
      end

      get '/funding' do
        handle_fundref(settings.fundref_branding)
      end

      get '/funding.csv' do
        handle_fundref(settings.fundref_branding)
      end

      get '/chorus' do
        handle_fundref(settings.chorus_branding)
      end

      get '/funders/:id/dois' do
        funder_id = params[:id]
        funder = @api.get_funder_info(funder_id)
        if funder["message"]
          qp = {
            :rows => query_rows,
            :page => query_page
          }
          result = @api.get_funder_id_works(funder_id,qp)
          result = result["message"]
          page = {
            :totalResults => result['total-results'],
            :startIndex => result['query']['start-index'],
            :itemsPerPage => query_rows,
            :query => {
              :searchTerms => funder_id,
              :startPage => query_page
            }
          }
          if result['items'].count > 0
            items = result['items'].map do |r|
              {
                :doi => r['URL'].sub("http://dx.","https://"),
                :deposited => r['deposited']['date-parts'].join("-"),
                :published => result_publication_date(r)
              }
            end
            page[:items] = items
          end
          content_type 'application/json'
          JSON.pretty_generate(page)
        else
          "No such funder identifier"
        end


      end

      get '/funders/:id/hierarchy' do
        funder = settings.funders.find_one({:id => params[:id]})
        page = {
          :funder => {
            :nesting => funder['nesting'],
            :nesting_names => funder['nesting_names'],
            :id => funder['id'],
            :country => funder['country'],
            :uri => funder['uri']
          }
        }
        haml :funder, :locals => {:page => page}
      end

      get '/funders/:id/hierarchy.csv' do
        content_type 'text/csv'
        CSV.generate do |csv|
          csv << ['Level 1', 'Level 2', 'Level 3']
          render_funders_full(params[:id], 0) do |indent, id, name|
            csv << ([""] * indent) + [name]
          end
        end
      end

      get '/funders/hierarchy' do
        funder_doi = params['doi']
        funder = settings.funders.find_one({:uri => funder_doi})
        page = {
          :funder => {
            :nesting => funder['nesting'],
            :nesting_names => funder['nesting_names'],
            :id => funder['id'],
            :country => funder['country'],
            :uri => funder['uri']
          }
        }
        haml :funder, :locals => {:page => page}
      end

      get '/funders/dois' do

        params = {
          :filter => 'has-funder:true',
          :rows => query_rows,
          :sort => 'deposited',
          :page => query_page,
          :order => 'desc'
        }
        result = @api.call("/works", params)
        result = result['message']
        items = result['items'].map do |r|
          {
            :doi => r['URL'].sub("http://dx.","https://"),
            :deposited => r["deposited"]["date-parts"].join("-"),
            :published => result_publication_date(r)
          }
        end

        page = {
          :totalResults => result['total-results'],
          :startIndex => result['query']['start-index'],
          :itemsPerPage => query_rows,
          :query => {
            :searchTerms => '',
            :startPage => query_page
          },
          :items => items
        }

        content_type 'application/json'
        JSON.pretty_generate(page)
      end

      get '/funders/prefixes' do
        # TODO Set rows to 'all'
        params = {
          :fl => 'doi',
          :q => 'funder_name:[* TO *]',
          :rows => 10000000,
        }
        result = settings.solr.paginate(query_page, query_rows, settings.solr_select, :params => params)
        dois = result['response']['docs'].map {|r| r['doi']}
        prefixes = dois.group_by {|doi| to_prefix(doi)}

        params = {
          :fl => 'doi',
          :q => 'funder_doi:[* TO *]',
          :rows => 10000000,
        }
        result = settings.solr.paginate(query_page, query_rows, settings.solr_select, :params => params)
        dois = result['response']['docs'].map {|r| r['doi']}
        with_id_prefixes = dois.group_by {|doi| to_prefix(doi)}

        combined = {}
        prefixes.each_pair do |prefix, items|
          combined[prefix] = {
            :total => items.count
          }
        end

        with_id_prefixes.each_pair do |prefix, items|
          combined[prefix] ||= {}
          combined[prefix][:with_id] = items.count
        end

        content_type 'text/csv'
        CSV.generate do |csv|
          csv << ['Prefix', 'Total work DOIs with funding data', 'Work DOIs with funder DOIs']
          combined.each_pair do |prefix, info|
            csv << [prefix, (info[:total] or 0), (info[:with_id] or 0)]
          end
        end
      end

      get '/funders/:id' do
        id = params["id"]
        funder = @api.get_funder_info(id)
        if funder["message"]
          funder = funder["message"]
          page = {
            :id => funder['id'],
            :country => funder['location'],
            :uri => funder['uri'].sub("http://dx.","https://"),
            :parent => @api.get_funder_parent(funder['hierarchy'],id),
            :children => funder['descendants'],
            :name => funder['name'],
            :alt => funder['alt-names']
          }
          content_type 'application/json'
          JSON.pretty_generate(page)
        else
          status 404
          'No such funder identifier'
        end
      end

      get '/funders' do

        descendants = ['1', 't', 'true'].include?(params['descendants'])
        qp = {
          :rows => query_rows,
          :page => query_page
        }
        if params['q']
          q = params['q'].gsub(/\"/,'')
          qp.merge!({:query => q})
        end

        results = @api.call("/funders",qp)
        datums = nil
        if results['message']["total-results"] > 0
          results = results['message']
          if params['format'] == 'csv'
            content_type 'text/csv'
            CSV.generate do |csv|
              results.each do |record|
                csv << [record['uri'], record['name']]
              end
            end
          else
            datums = results['items'].map do |result|
              base = {
                :id => result['id'],
                :country => result['location'],
                :uri => result['uri'],
                :value => result['name'],
                :other_names => result['alt-names'],
                :tokens => result['tokens'],
              }
              if descendants
                funder_info = @api.get_funder_info(result['id'])
                funder_info = funder_info["message"]
                h_names = funder_info["hierarchy-names"]
                d_names = {}
                if funder_info['descendants'].count > 0
                  funder_info['descendants'].each { |id|
                    d_names[id] = h_names[id]
                  }
                end
                base.merge({:descendants => funder_info['descendants'], :descendant_names => d_names})
              else
                base
              end
            end
          end
        end
        content_type 'application/json'
        unless datums.nil?
          JSON.pretty_generate(datums)
        else
          JSON.pretty_generate(results)
        end

      end

      get '/orcids/prefixes' do
        # TODO Set rows to 'all'
        params = {
          :fl => 'doi',
          :q => 'orcid:[* TO *]',
          :rows => 10000000,
        }
        result = settings.solr.paginate(query_page, query_rows, settings.solr_select, :params => params)
        dois = result['response']['docs'].map {|r| r['doi']}
        prefixes = dois.group_by {|doi| to_prefix(doi)}

        content_type 'text/csv'
        CSV.generate do |csv|
          csv << ['Prefix', 'Total DOI records with one or more ORCIDs']
          prefixes.each_pair do |prefix, items|
            csv << [prefix, items.count]
          end
        end
      end

      get '/' do
        if !params.has_key?('q') || !query_terms
          haml :splash, :locals => {
            :page => {
              :query => '',
              :stats => splash_stats,
              :branding => settings.crmds_branding
            }
          }
        else
          solr_result = select(search_query)
          page = result_page(solr_result)
          haml :results, :locals => {
            :page => page.merge({:branding => settings.crmds_branding})
          }
        end
      end

      get '/references' do
        haml :references, :locals => {
          :page => {:branding => settings.crmds_branding}
        }
      end

      post '/references' do
        refs_text = params['references'].strip

        if refs_text.empty?
          redirect '/references'
        else
          refs = refs_text.split("\n").reject{|r| r.nil? || r.strip.empty?}.map {|r| r.strip}
          resolved_refs = resolve_references(refs)

          haml :references_result, :locals => {
            :page => resolved_refs.merge({:branding => settings.crmds_branding})
          }
        end
      end

      get '/help/api' do
        redirect settings.api_documentation
      end

      get '/help/search' do
        haml :search_help, :locals => {
          :page => {
            :query => '',
            :branding => settings.crmds_branding
          }
        }
      end

      get '/help/status' do
        redirect settings.api_dashboard
      end

      get '/orcid/activity' do
        if signed_in?
          haml :activity, :locals => {
            :page => {
              :query => '',
              :branding => settings.crmds_branding
            }
          }
        else
          redirect '/'
        end
      end

      get '/orcid/claim' do
        status = 'oauth_timeout'

        if signed_in? && params['doi']
          doi = params['doi']
          plain_doi = to_doi(doi)
          orcid_record = settings.orcids.find_one({:orcid => sign_in_id})
          already_added = !orcid_record.nil? && orcid_record['locked_dois'].include?(plain_doi)

          if already_added
            status = 'ok'
          else
            # TODO: escape doi arg
            params = {
              :filter => "doi:#{doi}",
            }
            result = @api.call("/works", params)
            result = result['message']
            doi_record = nil
            doi_record = result['items'].first if result.key?("items")

            if doi_record.nil?
              status = 'no_such_doi'
            else
              if OrcidClaim.perform(session_info, doi_record)
                if orcid_record
                  orcid_record['updated'] = true
                  orcid_record['locked_dois'] << plain_doi
                  orcid_record['locked_dois'].uniq!
                  settings.orcids.save(orcid_record)
                else
                  doc = {:orcid => sign_in_id, :dois => [], :locked_dois => [plain_doi]}
                  settings.orcids.insert(doc)
                end

                # The work could have been added as limited or public. If so we need
                # to tell the UI.
                OrcidUpdate.perform(session_info)
                updated_orcid_record = settings.orcids.find_one({:orcid => sign_in_id})

                if updated_orcid_record['dois'].include?(plain_doi)
                  status = 'ok_visible'
                else
                  status = 'ok'
                end
              else
                status = 'oauth_timeout'
              end
            end
          end
        end

        content_type 'application/json'
        {:status => status}.to_json
      end

      get '/orcid/unclaim' do
        if signed_in? && params['doi']
          doi = params['doi']
          plain_doi = to_doi(doi)
          orcid_record = settings.orcids.find_one({:orcid => sign_in_id})

          if orcid_record
            orcid_record['locked_dois'].delete(plain_doi)
            settings.orcids.save(orcid_record)
          end
        end

        content_type 'application/json'
        {:status => 'ok'}.to_json
      end

      get '/orcid/sync' do
        status = 'oauth_timeout'

        if signed_in?
          if OrcidUpdate.perform(session_info)
            status = 'ok'
          else
            status = 'oauth_timeout'
          end
        end

        content_type 'application/json'
        {:status => status}.to_json
      end

      get '/dois' do
        qp = {
          :rows => query_rows,
          :page => query_page,
        }
        qp.merge!({:q => params['q']}) if params.key?('q')
        solr_result = @api.query(qp)
        items = search_results(solr_result).map do |result|
          {
            :doi => result.doi,
            :score => result.score,
            :normalizedScore => result.normal_score,
            :title => result.coins_atitle,
            :fullCitation => result.citation,
            :coins => result.coins,
            :year => result.coins_year
          }
        end

        content_type 'application/json'

        if ['true', 't', '1'].include?(params[:header])
          page = {
            :totalResults => solr_result['message']['total-results'],
            :startIndex => solr_result['message']['query']['start-index'],
            :itemsPerPage => query_rows,
            :query => {
              :searchTerms => params['q'],
              :startPage => query_page
            },
            :items => items
          }

          JSON.pretty_generate(page)
        else
          JSON.pretty_generate(items)
        end
      end

      post '/links' do
        citation_texts = JSON.parse(request.env['rack.input'].read)
        page = resolve_references(citation_texts)

        content_type 'application/json'
        JSON.pretty_generate(page)
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

      get '/auth/orcid/callback' do
        session[:orcid] = request.env['omniauth.auth']
        OrcidUpdate.perform(session_info)
        update_profile
        haml :auth_callback
      end

      get '/auth/orcid/import' do
        make_and_set_token(params[:code], settings.orcid_import_callback)
        OrcidUpdate.perform(session_info)
        update_profile
        redirect to("/?q=#{session[:orcid][:info][:name]}")
      end

      # Used to sign out a user but can also be used to mark that a user has seen the
      # 'You have been signed out' message. Clears the user's session cookie.
      get '/auth/signout' do
        session.clear
        redirect(params[:redirect_uri])
      end

      get '/heartbeat' do
        content_type 'application/json'

        params['q'] = 'fish'

        begin
          # Attempt a query with solr
          solr_result = select(search_query)

          # Attempt some queries with mongo
          result_list = search_results(solr_result)

          {:version => '1.0', :status => :ok}.to_json
        rescue StandardError => e
          {:version => '1.0', :status => :error, :type => e.class, :message => e}.to_json
        end
      end

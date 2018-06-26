require 'json'
require 'faraday'

class APICalls
  attr_reader :url, :token
  attr_writer :works_count, :funders_count, :results
  FACET_RESULT_COUNT = 10
  def initialize(url,token=nil)
    @url = Faraday.new(url)
    @url.headers.merge!({"Authorization" => token})
  end

  def count(type)
    if acceptable_count.include?(type)
      url_fragment = "/#{type}?rows=0"
      response = @url.get(url_fragment)
      JSON.parse(response.body)['message']['total-results']
    else
      raise ArgumentError, "#{type} is not on the list of acceptable arguments: #{acceptable_count.join(",")}"
    end
  end

  def call(url_fragment)
    url = "/#{url_fragment}"
    response = @url.get(url_fragment)
    JSON.parse(response.body)['message']['total-results']
  end

  def query(query_params)
    url = "/works"
    @query_params = query_params
    process_query_params
    url = query_type(url)
    get_response(url)
  end


  private

  def process_query_params
    @rows = @query_params[:rows].to_i
    @page = @query_params[:page].to_i
    @filter = @query_params[:filter_query] if @query_params.key?(:filter_query)
    if @filter
      filter_params = process_filter
      @query_params.delete(:filter_query)
      filter_params.each_pair { |k,v|
        value = k == :filter ? v.join(",") : v
        @query_params[k] = value
      }
    end
    @query_params.delete(:page)
    offset = @page > 1 ? get_offset : nil
    @query_params.merge!(:offset => offset) unless offset.nil?
    @facet_fields = @query_params[:facet]
    facets = explode_facets
    facet_url = facets.join(",")
    @query_params[:facet] = facet_url
  end


  def get_response(url)
    rsp = @url.get(url)
    JSON.parse(rsp.body)
  end

  def query_type(url)
    url_array = []
    @query_params.each_pair { |f,v|
      url_array << "#{f}=#{v}" unless f == :q
    }
    case @query_params[:q]
    when /^doi\:/
      search_param = @query_params[:q].split("doi:")[1]
      url += doi_works_query
    when /^issn\:/
      url = issn_journals_query
    when /^orcid\:/
      url += "?filter=#{@query_params[:q]}"
    else
      url += keywords_works_query
    end
    url += url_array.join("&")
  end

  def keywords_works_query
    "?query=#{@query_params[:q]}"
  end

  def doi_works_query
    #search_param = @query_params[:q].split("doi:")[1]
    #{}"/#{search_param}?"
    "?query=#{search_param}"
  end

  def issn_journals_query
    search_param = @query_params[:q].split("issn:")[1]
    "/journals/#{search_param}/works?"
  end

  def acceptable_count
    %w(works funders members types licenses journals)
  end

  def explode_facets
    @facet_fields.map { |f| "#{f}:#{FACET_RESULT_COUNT}" }
  end

  def get_offset
    @rows * (@page - 1)
  end

  def process_filter
    url={}
    url[:filter] = [] #initializing array
    @filter.each { |f|
      field,value = f.split(":")
      case
      when filter_types.include?(field)
       field = map_filter_names.key?(field) ? map_filter_names[field] : field
       url[:filter] << "#{field}:#{value}"
      when query_field_names.include?(field)
       k = "query.#{field}".to_sym
       url[k] = value
      end
    }
    url.delete(:filter) if url[:filter].empty?
    url
  end

  def map_filter_names
    { "published" => "from-pub-date" }
  end


  def filter_types
    ["type-name","published","container-title"]
  end

  def query_field_names
    ["publisher-name","funder-name"]
  end
end

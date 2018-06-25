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
    @rows = query_params[:rows].to_i
    @page = query_params[:page].to_i
    @filter = query_params[:filter_query] if query_params.key?(:filter_query)
    # change query param to either query.field name or filter depending on field name
    if @filter
      filter_params = process_filter
      query_params.delete(:filter_query)
      filter_params.each_pair { |k,v|
        value = k == :filter ? v.join(",") : v
        query_params[k] = value
      }
    end
    query_params.delete(:page)
    offset = @page > 1 ? get_offset : nil
    query_params.merge!(:offset => offset) unless offset.nil?
    url = "/works?"
    url_array = []
    @facet_fields = query_params[:facet]
    facets = explode_facets
    facet_url = facets.join(",")
    query_params[:facet] = facet_url

    query_params.each_pair { |f,v|
      f = f == :q ? "query" : f
      url_array << "#{f}=#{v}"
    }
    url += url_array.join("&")
    rsp = @url.get(url)
    JSON.parse(rsp.body)
  end


  private

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

require 'json'
require 'faraday'

class APICalls
  attr_reader :url, :query, :mailto
  attr_writer :works_count, :funders_count, :results

  def initialize(url,mailto=nil,query=nil)
    @url = Faraday.new(url)
    @url.headers.merge!({"mailto" => mailto})
    @query = query
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
    @facet_fields.map { |f| "#{f}:*" }
  end
end

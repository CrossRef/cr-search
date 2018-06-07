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


  private

  def acceptable_count
    %w(works funders members types licenses journals)
  end
end

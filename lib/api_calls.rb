require 'json'
require 'faraday'

class APICalls
  attr_reader :url, :token
  attr_writer :works_count, :funders_count, :results
  FACET_RESULT_COUNT = 10
  def initialize(url,token=nil)
    @url = Faraday.new(url)
    auth_header = {"Authorization" => token}
    @url.headers.merge!(auth_header) unless token.nil?
  end

  def count(type,filter=nil)
    if acceptable_count.include?(type)
      url_fragment = "/#{type}?rows=0"
      url_fragment += "&filter=#{filter}" unless filter.nil?
      response = @url.get(url_fragment)
      JSON.parse(response.body)['message']['total-results']
    else
      raise ArgumentError, "#{type} is not on the list of acceptable arguments: #{acceptable_count.join(",")}"
    end
  end

  def call(query)
    response = @url.get(query)
    JSON.parse(response.body)['message']
  end

  def get_funder_info(id)
    query = "#{funders_url}/#{id}"
    rsp = get_response(query)
    rsp['message']
  end

  def get_funder_parent(hierarchy,id)
  parent = nil
  if hierarchy.keys[0] == id
  else
    hierarchy.values[0].each_pair { |k,v|
      if k == id
        parent = hierarchy.keys[0]
      elsif v.key?(id)
        parent = k
      end
    }
  end
  parent
  end

  def get_funder_id_works(id,query_params)
    url = "#{funders_url}/#{id}#{works_url}"
    rsp = handle_query(url,query_params)
    rsp['message']
  end

  def query(query_params)
    handle_query(works_url,query_params)
  end

  def handle_query(url,query_params)
    query_url = {}
    query_url[:query] = url
    @query_params = query_params
    process_query_params
    url = query_type(query_url)
    url = url[:query]+"?"+url[:remaining_url]
    get_response(url)
  end

  def index_stats(orcids = nil)
    stats = []
    hsh = {}
    total_indexed_dois = count("works").to_i
    books = []
    book_types.each { |b|
        books << filter_type_name(b)
    }
    books = books.join(",")
    hsh["book_types"] = count("works",books).to_i
    status_types.each { |f|
      hsh[f] = count("works",filter_type_name(f)).to_i
    }
    total_dataset_result = hsh["Dataset"] + hsh["Component"]
    total_dois_funding_data = count("works","has-funder:true")
    total_works_funder_dois = count("works","has-funder-doi:true")
    total_dois_with_orcids = count("works","has-orcid:true")
    stats << {
      :value => total_indexed_dois,
      :name => 'Total number of indexed DOIs',
      :number => true
    }

    stats << {
      :value => hsh["Journal Article"],
      :name => 'Number of indexed journal articles',
      :number => true
    }

    stats << {
      :value => hsh["Conference Paper"],
      :name => 'Number of indexed conference papers',
      :number => true
    }

    stats << {
      :value => hsh["book_types"],
      :name => 'Number of indexed book-related DOIs',
      :number => true
    }

    stats << {
      :value => total_dataset_result,
      :name => 'Number of indexed figure, component and dataset DOIs',
      :number => true
    }

    stats << {
      :value => hsh["Standard"],
      :name => 'Number of indexed standards',
      :number => true
    }

    stats << {
      :value => hsh["Report"],
      :name => 'Number of indexed reports',
      :number => true
    }
    stats << {
      :value => total_works_funder_dois,
      :name => 'Number of work DOIs with funder DOIs',
      :number => true
    }

    stats << {
      :value => total_dois_funding_data,
      :name => 'Total number of DOIs with funding data',
      :number => true
    }

    stats << {
      :value => total_dois_with_orcids,
      :name => 'Number of indexed DOIs with associated ORCIDs',
      :number => true
    }

    if orcids
      stats << {
        :value => orcids.count({:query => {:updated => true}}),
        :name => 'Number of ORCID records updated',
        :number => true
      }
    end

    stats
  end

  private
  def works_url
    "/works"
  end

  def funders_url
    "/funders"
  end
  def filter_type_name(type)
    allowed_types = status_types + filter_types + book_types
    "type-name:#{type}" if allowed_types.include?(type)
  end

  def status_types
    ["Journal Article","Conference Paper","Standard","Report","Dataset","Component"]
  end

  def book_types
    ['Book', 'Book Series', 'Book Set', 'Reference',
     'Monograph', 'Chapter', 'Section', 'Part', 'Track', 'Entry']
  end
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
    if @query_params[:facet]
      @facet_fields = @query_params[:facet]
      facets = explode_facets
      facet_url = facets.join(",")
      @query_params[:facet] = facet_url
    end
  end


  def get_response(url)
    rsp = @url.get(url)
    JSON.parse(rsp.body)
  end

  def query_type(url_hsh)
    url_array = []
    url = ""
    @query_params.each_pair { |f,v|
      field = f == :q ? "query.bibliographic" : f
      if f == :q && v =~ /^issn\:/
        url_hsh[:query] = issn_journals_query
      else
        url_array << "#{field}=#{v}"
      end
    }
    url_hsh[:remaining_url] = url_array.join("&")
    url_hsh
  end

  def keywords_works_query
    "query.bibliographic=#{@query_params[:q]}"
  end

  def filter_works_query
    "filter=#{@query_params[:q]}&"
  end

  def issn_journals_query
    search_param = @query_params[:q].split("issn:")[1]
    "/journals/#{search_param}/works"
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
    ["type-name","published","container-title","funder","doi","orcid"]
  end

  def query_field_names
    ["publisher-name","funder-name"]
  end
end

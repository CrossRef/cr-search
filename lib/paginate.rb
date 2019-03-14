require 'will_paginate'

class Paginate

  def initialize page, per_page, solr_response
    @page = page
    @per_page = per_page
    @response = solr_response['message']
    @total_page_limit = 10
  end

  def docs
    @response['items']
  end

  def per_page
    @per_page
  end

  def current_page
    @page
  end

  def total_pages
    [(@response['total-results'] / per_page.to_f).ceil, @total_page_limit].min
  end

  def total_rows
    @response['total-results']
  end

end

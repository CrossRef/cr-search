require 'will_paginate'

class Paginate
  attr_reader :current_page, :per_page, :total_results

  def initialize current_page, per_page, total_results
    @current_page = current_page
    @per_page = per_page
    @total_results = total_results
  end

  def total_pages
    (@total_results / @per_page.to_f).ceil
  end
end

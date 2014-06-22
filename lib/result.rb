# -*- coding: utf-8 -*-
require 'csv'

class SearchResult

  attr_reader :year, :month, :day
  attr_reader :title, :volume, :issue
  attr_reader :short_publication, :long_publication
  alias_method :publication, :long_publication
  attr_reader :first_page, :last_page
  attr_reader :type, :url, :score
  attr_reader :funders
  attr_reader :authors
  attr_reader :doi, :supplementary_id
  alias_method :supplementary_id, :doi

  ENGLISH_MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
                    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec']

  def initialize item, funders_names
    @url = item['URL']
    @type = item['type'].sub('-', ' ').capitalize
    @score = item['score']
    publications = item['container-title'].sort_by(&:length)
    @short_publication, @long_publication = publications.first, publications.last
    @title = item['title'][0]
    @year, month, @day = item['issued']['date-parts'][0]
    @month = ENGLISH_MONTHS[month - 1] if month
    @volume = item['volume']
    @issue = item['issue']
    @authors = if item['author']
                 item['author'].map { |author| author_full_name(author) }
               else
                 []
               end
    @first_page, @last_page = item['page'].split("-") if item['page']
    @funders = funders_names.values_at(*funders_ids(item))
    @doi = item['DOI']
  end

  def self.results_from_items(items, funders_names)
    items.map { |item| SearchResult.new item, funders_names }
  end

  def self.generate_csv(results)
    CSV.generate do |csv|
      csv << ['DOI', 'Type', 'Year', 'Title', 'Publication', 'Authors', 'Funders']
      results.each do |result|
        csv << [result.doi, result.type, result.year, result.title, result.publication,
          result.authors.join(', '), result.funders.join(', ')]
      end
    end
  end

  private
    def author_full_name(author)
      "#{author['family']} #{author['given']}"
    end

    def funders_ids(item)
      item['funder'].map { |funder| remove_prefix(funder['DOI']) }
    end

    def remove_prefix(id_with_prefix)
      id_with_prefix.split('/')[1]
    end
end

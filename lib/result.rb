# -*- coding: utf-8 -*-
require 'cgi'

require_relative 'doi'

class SearchResult

  include Doi

  attr_accessor :year, :month, :day
  attr_accessor :title, :publication, :volume, :issue
  attr_accessor :first_page, :last_page
  attr_accessor :type, :doi, :score, :normal_score, :display_doi
  attr_accessor :citations, :hashed
  attr_accessor :funder_names, :grant_info, :plain_funder_names
  attr_accessor :editors, :translators, :chairs , :contributors, :authors
  attr_accessor :supplementary_ids

  ENGLISH_MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec']

    def parse_people(people)
      name = []
      people.each { |p|
        name << "#{p["given"]} #{p["family"]}"
      }
      name
    end

    def parse_pages(pages)
      first_page,last_page = nil
      first_page,last_page = pages.split("-") if pages =~ /-/
    end

    def parse_funders(funder)
      funder_info = []
      funder.each { |f|
        award = f["award"].count > 0 ? " (#{f["award"].join("")})" : ""
        funder_info << "#{f["name"]}#{award}"
      }
      funder_info
    end

    def get_date
      dates = nil
      if @doc["published-print"] || @doc["published-online"]
        date = @doc["published-print"].nil? ? @doc["published-online"] : @doc["published-print"]
        dates = date["date-parts"].first
      end
      dates
    end
    # Merge a mongo DOI record with solr highlight information.
    def initialize solr_doc, solr_result, citations, user_state
      @doi = solr_doc['DOI']
      puts @doi
      @display_doi = to_long_display_doi(solr_doc['DOI'])
      @type = solr_doc['type']

      @doc = solr_doc
      @score = solr_doc['score']
      @score = @normal_score
      @citations = citations
      @hashed =  Digest::MD5.hexdigest(solr_doc['DOI'])
      @user_claimed = user_state[:claimed]
      @in_user_profile = user_state[:in_profile]
      @publication = solr_doc["container-title"][0] if solr_doc["container-title"]
      @title = solr_doc["title"][0] if solr_doc["title"]
      @year, month, @day = get_date
      @month = ENGLISH_MONTHS[month.to_i - 1] if month
      @volume = solr_doc["volume"] if solr_doc["volume"]
      @issue = solr_doc["issue"] if solr_doc["issue"]
      # optimize people
      @authors = parse_people(solr_doc["author"]) if solr_doc["author"]
      @editors = parse_people(solr_doc["editor"]) if solr_doc["editor"]
      @translators = parse_people(solr_doc['translator']) if solr_doc["translator"]

      @chairs = parse_people(solr_doc['chair']) if solr_doc["chair"]
      @contributors = []
      @first_page,@last_page = parse_pages(solr_doc['page']) if solr_doc["page"]
      @funder_names = []
      if solr_doc["funder"]
        solr_doc["funder"].each { |f|
          @funder_names << f["name"]
        }
      end
      @plain_funder_names = @funder_names unless @funder_names.nil?
      @grant_info = parse_funders(solr_doc["funder"]) if solr_doc["funder"]

      if solr_doc['alternative-id'].nil?
        @supplementary_ids = []
      else
        @supplementary_ids = solr_doc['alternative-id']
      end
    end

    def award_numbers
      award_numbers = []

      @grant_info.each do |funder_awards|
        funder_awards = funder_awards.strip()
        if funder_awards.end_with?(')')
          from = funder_awards.rindex(/\([^\)]+\)\Z/)
          if !from.nil?
            awards = funder_awards[(from+1)..-2]
            awards.split(',').each do |award_number|
              award_numbers << award_number.strip
            end
          end
        end
      end

      award_numbers.join(', ')
    end

    def doi
      @doi
    end

    def open_access?
      @doc['oa_status'] == 'DOAJ'
    end

    def user_claimed?
      @user_claimed
    end

    def in_user_profile?
      @in_user_profile
    end

    def coins_atitle
      @title if @title
    end

    def coins_title
      @publication if @publication
    end

    def coins_year
      @year
    end

    def coins_volume
      @volume if @volume
    end

    def coins_issue
      @issue if @issue
    end

    def coins_spage
      @first_page if @first_page
    end

    def coins_lpage
      @last_page if @last_page
    end

    def coins_authors
      authors = @authors.nil? ? '' : @authors.join(",")
    end

    def coins_au_first
      fa = nil
      if @authors
        a = []
        first_author = @authors[0].split(" ")
        first_author.each { |i| a << i unless i == first_author.last }
        fa = a.join(" ")
      end
      fa
    end

    def coins_au_last
      fa_lastname = nil
      if @authors
        first_author = @authors[0].split(" ")
        fa_lastname = first_author.last
      end
      fa_lastname
    end

    def coins
      props = {
        'ctx_ver' => 'Z39.88-2004',
        'rft_id' => "info:doi/#{@doi}",
        'rfr_id' => 'info:sid/crossref.org:search',
        'rft.atitle' => coins_atitle,
        'rft.jtitle' => coins_title,
        'rft.date' => coins_year,
        'rft.volume' => coins_volume,
        'rft.issue' => coins_issue,
        'rft.spage' => coins_spage,
        'rft.epage' => coins_lpage,
        'rft.aufirst' => coins_au_first,
        'rft.aulast' => coins_au_last,
      }

      case @type
      when 'Journal Article'
        props['rft_val_fmt'] = 'info:ofi/fmt:kev:mtx:journal'
        props['rft.genre'] = 'article'
      when 'Conference Paper'
        props['rft_val_fmt'] = 'info:ofi/fmt:kev:mtx:journal'
        props['rft.genre'] = 'proceeding'
      when 'Proceedings'
        props['rft_val_fmt'] = 'info:ofi/fmt:kev:mtx:journal'
        props['rft.genre'] = 'conference'
      when 'Journal Issue'
        props['rft_val_fmt'] = 'info:ofi/fmt:kev:mtx:journal'
        props['rft.genre'] = 'issue'
      when 'Book'
        props['rft_val_fmt'] = 'info:ofi/fmt:kev:mtx:book'
        props['rft.genre'] = 'book'
      when 'Monograph'
        props['rft_val_fmt'] = 'info:ofi/fmt:kev:mtx:book'
        props['rft.genre'] = 'book'
      when 'Reference'
        props['rft_val_fmt'] = 'info:ofi/fmt:kev:mtx:book'
        props['rft.genre'] = 'book'
      when 'Report'
        props['rft_val_fmt'] = 'info:ofi/fmt:kev:mtx:book'
        props['rft.genre'] = 'report'
      when 'Chapter'
        props['rft_val_fmt'] = 'info:ofi/fmt:kev:mtx:book'
        props['rft.genre'] = 'bookitem'
      when 'Entry'
        props['rft_val_fmt'] = 'info:ofi/fmt:kev:mtx:book'
        props['rft.genre'] = 'bookitem'
      when 'Track'
        props['rft_val_fmt'] = 'info:ofi/fmt:kev:mtx:book'
        props['rft.genre'] = 'bookitem'
      when 'Part'
        props['rft_val_fmt'] = 'info:ofi/fmt:kev:mtx:book'
        props['rft.genre'] = 'bookitem'
      else
        props['rft_val_fmt'] = 'info:ofi/fmt:kev:mtx:unknown'
        props['rft.genre'] = 'unknown'
      end

      title_parts = []

      props.reject { |_, value| value.nil? }.each_pair do |key, value|
        title_parts << "#{key}=#{CGI.escape(value.to_s)}"
      end

      title = title_parts.join('&')
      #binding.pry if @doc["DOI"] == "10.1007/978-1-4842-2778-7_2"
      coins_authors.split(',').each { |author| title += "&rft.au=#{CGI.escape(author)}" }

      CGI.escapeHTML title
    end

    def coins_span
      "<span class=\"Z3988\" title=\"#{coins}\"><!-- coins --></span>"
    end

    # Mimic SIGG citation format.
    def citation
      a = []
      a << CGI.escapeHTML(coins_authors) unless coins_authors.empty?
      a << CGI.escapeHTML(coins_year.to_s) unless coins_year.nil?
      a << "'#{CGI.escapeHTML(coins_atitle)}'" unless coins_atitle.nil?
      a << "<i>#{CGI.escapeHTML(coins_title)}</i>" unless coins_title.nil?
      a << "vol. #{CGI.escapeHTML(coins_volume)}" unless coins_volume.nil?
      a << "no. #{CGI.escapeHTML(coins_issue)}" unless coins_issue.nil?

      if !coins_spage.nil? && !coins_lpage.nil?
        a << "pp. #{CGI.escapeHTML(coins_spage)}-#{CGI.escapeHTML(coins_lpage)}"
      elsif !coins_spage.nil?
        a << "p. #{CGI.escapeHTML(coins_spage)}"
      end

      a.join ', '
    end
  end

# -*- coding: utf-8 -*-
require 'nokogiri'
require 'oauth2'
require 'open-uri'

require_relative 'data'
require_relative 'doi'

class OrcidClaim
  include Doi

  @queue = :orcid

  ORCID_VERSION = '2.0'

  def initialize oauth, work
    @oauth = oauth
    @work = work
  end

  def self.perform oauth, work
    OrcidClaim.new(oauth, work).perform
  end

  def perform
    oauth_expired = false

    begin
      load_config

      # Need to check both since @oauth may or may not have been serialized back and forth from JSON.
      uid = @oauth[:uid] || @oauth['uid']
      orcid_redirect_uri = ENV["ORCID_REDIRECT_URI"]
      orcid_client_id = ENV["ORCID_CLIENT_ID"]
      orcid_client_secret = ENV["ORCID_CLIENT_SECRET"]
      #$stderr.puts to_xml

      opts = {:site => @conf['orcid_site'], :redirect_uri => orcid_redirect_uri }
      client = OAuth2::Client.new(orcid_client_id, orcid_client_secret, opts)
      token = OAuth2::AccessToken.new(client, @oauth['credentials']['token'])
      headers = {'Accept' => 'application/vnd.json+xml'}
      response = token.post("#{@conf['orcid_site']}/v#{ORCID_VERSION}/#{uid}/work") do |post|
        post.headers['Content-Type'] = 'application/vnd.orcid+xml'
        post.body = to_xml
      end
      #$stderr.puts response
      oauth_expired = response.status >= 400
    rescue StandardError => e
      oauth_expired = true
      #$stderr.puts e
    end

    !oauth_expired
  end

  def orcid_work_type internal_work_type
    case internal_work_type
    when 'Journal Article' then 'journal-article'
    when 'Conference Paper' then 'conference-paper'
    when 'Dissertation' then 'dissertation'
    when 'Report' then 'report'
    when 'Standard' then 'standards-and-policy'
    when 'Dataset' then 'data-set'
    when 'Book' then 'book'
    when 'Reference' then 'book'
    when 'Monograph' then 'book'
    else 'other'
    end
  end

  def pad_date_item item
    result = nil
    if item
      begin
        item_int = item.to_s.strip.to_i
        if item_int >= 0 && item_int <= 11
          item_str = item_int.to_s
          if item_str.length < 2
            result = "0" + item_str
          elsif item_str.length == 2
            result = item_str
          end
        end
      rescue StandardError => e
        # Ignore type conversion errors
      end
    end
    result
  end

  def to_issn uri
    uri.strip.sub(/\Ahttp:\/\/id.crossref.org\/issn\//, '')
  end

  def to_isbn uri
    uri.strip.sub(/\Ahttp:\/\/id.crossref.org\/isbn\//, '')
  end

  def insert_id xml, type, value, rel
    xml['common'].send(:'external-id') {
      xml['common'].send(:'external-id-type', type)
      xml['common'].send(:'external-id-value', value)
      xml['common'].send(:'external-id-relationship', rel)
    }
  end

  def insert_ids xml
     xml['common'].send(:'external-ids') {
       insert_id(xml, 'doi', @work['DOI'], 'self')
       insert_id(xml, 'isbn', to_isbn(@work['ISBN'].first), 'part-of') if @work['isbn'] && !@work['ISBN'].empty?
       insert_id(xml, 'issn', to_issn(@work['ISSN'].first), 'part-of') if @work['ISSN'] && !@work['ISSN'].empty?
    }
  end

  def insert_pub_date xml
    year,month,day = nil
    ["published-print","published-online"].each do |pub|
      year,month,day = @work[pub]["date-parts"].first if @work.key?(pub)
    end
    month_str = pad_date_item(month) unless (month.nil?)
    day_str = pad_date_item(day) unless (day.nil?)
    if year
      xml['common'].send(:'publication-date') {
        xml['common'].year(year.to_i.to_s)
        xml['common'].month(month_str) if month_str
        xml['common'].day(day_str) if month_str && day_str
      }
    end
  end

  def insert_type xml
    # commenting this out since the returned type from the method orcid_work_type seems to match the api response
    #xml['work'].type orcid_work_type(@work['type'])
    xml['work'].type @work['type']
  end

  def insert_titles xml
    subtitle = nil
    if @work['subtitle'] && !@work['subtitle'].empty?
      subtitle = @work['subtitle'].first
    end

    if subtitle || @work['title']
      xml['work'].title {
        if @work['title'] && !@work['title'].empty?
          xml['common'].title(without_control(@work['title'].first))
        end
        if subtitle
          xml['common'].subtitle(without_control(subtitle))
        end
      }
    end

    if @work["container-title"]
      xml['work'].send(:'journal-title', @work["container-title"])
    end
  end

  def insert_contributors xml
    xml['work'].contributors {
      ['author', 'editor'].each do |role|
        if !@work[role].nil?
          @work[role].each do |r|
            credit = "#{r["given"]} #{r["family"]}"
            xml['work'].contributor {
              xml['work'].send(:'credit-name', credit.strip())
              xml['work'].send(:'contributor-attributes') {
                xml['work'].send(:'contributor-role', role)
              }
            }
          end
        end
      end
    }
  end

  def insert_citation xml
    conn = Faraday.new
    response = conn.get "https://data.crossref.org/#{URI.encode(@work['DOI'])}", {}, {
      'Accept' => 'application/x-bibtex'
    }

    if response.status == 200
      xml['work'].citation {
        xml['work'].send(:'citation-type', 'bibtex')
        xml['work'].send(:'citation-value', (without_control(response.body)))
      }
    end
  end

  def without_control s
    r = ''
    s.each_codepoint do |c|
      if c >= 32
        r << c
      end
    end
    r
  end

  def to_xml
    root_attributes =
      {
       :'xmlns:xsi' => 'http://www.w3.org/2001/XMLSchema-instance',
       :'xmlns:common' => 'http://www.orcid.org/ns/common',
       :'xmlns:work' => 'http://www.orcid.org/ns/work',
       :'xsi:schemaLocation' => 'http://www.orcid.org/ns/work /work-2.0.xsd',
      }

    Nokogiri::XML::Builder.new do |xml|
      xml['work'].work(root_attributes) {
        insert_titles(xml)
        insert_citation(xml)
        insert_type(xml)
        insert_pub_date(xml)
        insert_ids(xml)
        insert_contributors(xml)
      }
    end.to_xml
  end

  def load_config
    @conf ||= {}
    config = JSON.parse(File.open('conf/app.json').read)
    config.each_pair do |key, value|
      @conf[key] = value
    end
  end

end

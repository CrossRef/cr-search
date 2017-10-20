# -*- coding: utf-8 -*-
require 'nokogiri'
require 'oauth2'

require_relative 'data'

class OrcidUpdate

  @queue = :orcid

  ORCID_VERSION = '2.0'

  def initialize oauth
    @oauth = oauth
  end

  def self.perform oauth
    OrcidUpdate.new(oauth).perform
  end

  def perform
    oauth_expired = false

    begin
      load_config

      # Need to check both since @oauth may or may not have been serialized back and forth from JSON.
      uid = @oauth[:uid] || @oauth['uid']

      opts = {:site => @conf['orcid_site']}
      client = OAuth2::Client.new(@conf['orcid_client_id'], @conf['orcid_client_secret'], opts)
      token = OAuth2::AccessToken.new(client, @oauth['credentials']['token'])
      headers = {'Accept' => 'application/vnd.orcid+json'}
      response = token.get "#{@conf['orcid_site']}/v#{ORCID_VERSION}/#{uid}/works", {:headers => headers}

      if response.status == 200
        response_json = JSON.parse(response.body)
        parsed_dois = parse_dois(response_json)
        query = {:orcid => uid}
        orcid_record = MongoData.coll('orcids').find_one(query)

        if orcid_record
          orcid_record['dois'] = parsed_dois
          MongoData.coll('orcids').save(orcid_record)
        else
          doc = {:orcid => uid, :dois => parsed_dois, :locked_dois => []}
          MongoData.coll('orcids').insert(doc)
        end
      else
        oauth_expired = true
      end
    rescue StandardError => e
      $stderr.puts e
    end

    !oauth_expired
  end

  def has_path? hsh, path
    loc = hsh
    path.each do |path_item|
      if loc[path_item]
        loc = loc[path_item]
      else
        loc = nil
        break
      end
    end
    loc != nil
  end

  def parse_dois json
    if !has_path?(json, ['group'])
      []
    else
      works = json['group']
      
      extracted_dois = works.map do |work_loc|
        doi = nil
        if has_path?(work_loc, ['external-ids', 'external-id'])
          ids_loc = work_loc['external-ids']['external-id']

          ids_loc.each do |id_loc|
            id_type = id_loc['external-id-type']
            id_val = id_loc['external-id-url']

            if id_type.upcase == 'DOI'
              doi = id_val
            end
          end

        end
        doi
      end

      extracted_dois.compact
    end
  end

  def load_config
    @conf ||= {}
    config = JSON.parse(File.open('conf/app.json').read)
    config.each_pair do |key, value|
      @conf[key] = value
    end
  end

end


# -*- coding: utf-8 -*-
module Doi

  JSON_TYPE = 'application/vnd.citationstyles.csl+json'

  def doi? s
    to_doi(s) =~ /\A10\.[0-9]{4,}\/.+/
  end

  # Short DOIs are of the form 10/abcde. These must be used with
  # doi.org.
  def short_doi? s
    to_doi(s) =~ /\A10\/[a-z0-9]+\Z/
  end

  # Very short DOIs are of the form abcde. These must be used with
  # doi.org. We check for doi.org/ since characters only preclude 
  # search terms.
  def very_short_doi? s
    s.strip =~ /\A(https?:\/\/)?doi\.org\/[a-z0-9]+\Z/
  end

  def issn? s
    s.strip.upcase =~ /\A[0-9]{4}\-[0-9]{3}[0-9X]\Z/
  end

  def to_prefix s
    s.match(/http:\/\/dx\.doi\.org\/(10\.\d+)\/.+/).captures.first
  end
    
  def to_doi s
    s = s.strip.sub(/\A(https?:\/\/)?dx\.doi\.org\//, '').sub(/\Adoi:/, '')
    s.sub(/\A(https?:\/\/)?doi.org\//, '')
  end

  def to_long_display_doi s
    doi = to_doi(s)
    "https://doi.org/#{doi}"
  end

  def to_long_doi s
    doi = to_doi(s)
    normal_short_doi = doi.sub(/10\//, '').downcase

    short_doi_doc = settings.shorts.find(:short_doi => normal_short_doi)

    if short_doi_doc.has_next?
      short_doi_doc.next['doi']
    else
      res = settings.doi_org.get do |req|
        req.url "/10/#{normal_short_doi}"
        req.headers['Accept'] = JSON_TYPE
      end
      
      if res.success?
        doi = JSON.parse(res.body)['DOI']
        settings.shorts.insert({:short_doi => normal_short_doi, :doi => doi})
        doi
      end
    end
  end

end

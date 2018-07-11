require 'spec_helper'

describe "actions on the results page", vcr: true do
    search_bar = "#search-input"
    before(:each) do
      visit '/?q=josiah+carberry'
    end
    it 'renders' do
      expect(page.status_code).to be 200
    end
    it 'has a search bar' do
      expect(page).to have_selector("#search-input")
    end
    it 'has the query term in the search bar' do
      query = page.find("//input[@id = 'search-input']").value
      expect(query).to eq("josiah carberry")
    end
    it 'outputs page number and number of results' do
      expect(page).to have_css("h6.number", text: "Page 1 of 5617 results")
    end
    it 'outputs 10 results on first page' do
      expect(page).to have_css("td.item-data", count: 10)
    end
    it 'outputs 5 facet headings' do
      expect(page).to have_css("div.mini-page-header", count: 5)
    end
    it 'outputs 10 facet values per facet if they exist' do
      facet_headings = all("div.mini-page-header")
      pos = 1
      facet_headings.each { |fh|
        value_count = all(:xpath,"#{fh.path}/../ul[#{pos}][@class='nav nav-list']/li").count
        expect(value_count).to eql(10)
        pos += 1
      }
    end
end

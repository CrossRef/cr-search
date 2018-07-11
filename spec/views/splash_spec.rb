require 'spec_helper'

describe "actions on the splash page", vcr: true do
    search_bar = "#search-input"
    before(:each) do
      visit '/'
    end
    it 'renders' do
      expect(page.status_code).to be 200
    end
    it 'has a search bar' do
      expect(page).to have_selector("#search-input")
    end
    it 'has a number of indexed works in the text' do
      number = page.find("//span[@class = 'number']").text.to_i
      expect(number).to be > 0
    end

end

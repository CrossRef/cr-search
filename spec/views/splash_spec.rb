require 'spec_helper'

describe "actions with the splash page", vcr: true do
  #context "renders the splash page with a search bar and the number of indexed works" do
    before(:each) do
      visit '/'
    end
    it 'should render' do
      expect(page.status_code).to be 200
    end
    it 'should have a search bar' do
      expect(page).to have_selector("#search-input")
    end
    it 'should have a number of indexed works in the text' do
      number = page.find("//span[@class = 'number']").text.to_i
      expect(number).to be > 0
    end
  #end
end

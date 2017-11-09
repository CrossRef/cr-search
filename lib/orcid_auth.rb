require 'omniauth-oauth2'

module OmniAuth
  module Strategies
    class Orcid < OmniAuth::Strategies::OAuth2

      @conf ||= {}
      config = JSON.parse(File.open('conf/app.json').read)
      config.each_pair do |key, value|
        @conf[key] = value
      end

      option :client_options, {
        :scope => '/read-limited /activities/update',
        :response_type => 'code',
        :mode => :header,
        :redirect_uri => @conf['orcid_redirect_uri']
      }

      uid { access_token.params["orcid"] }

      info do {} end

      def callback_url
        puts @conf['orcid_redirect_uri']
        @conf['orcid_redirect_uri']
      end

      # Customize the parameters passed to the OAuth provider in the authorization phase
      def authorize_params
        # Trick shamelessly borrowed from the omniauth-facebook gem!
        super.tap do |params|
          %w[scope].each { |v| params[v.to_sym] = request.params[v] if request.params[v] }
          params[:scope] ||= '/read-limited /activities/update' 
          # ensure that we're always request *some* default scope

          params[:redirect_uri] = @conf['orcid_redirect_uri']
        end
      end
    end
  end
end

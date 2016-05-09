require 'json'

module Session
  def auth_token
    OAuth2::AccessToken.new settings.orcid_oauth, session[:orcid]['credentials']['token']
  end

  def make_and_set_token code, redirect
    token_obj = settings.orcid_oauth.auth_code.get_token(code, {:redirect_uri => redirect})
    session[:orcid] = {
      'credentials' => {
        'token' => token_obj.token
      },
      :uid => token_obj.params['orcid'],
      :info => {}
    }
  end

  def update_profile
    response = auth_token.get "#{session[:orcid][:uid]}/orcid-profile", :headers => {'Accept' => 'application/json'}
    if response.status == 200
      json = JSON.parse(response.body)
      session[:orcid][:info][:name] = session[:orcid]
      begin
        given_name = json['orcid-profile']['orcid-bio']['personal-details']['given-names']['value']
        family_name = json['orcid-profile']['orcid-bio']['personal-details']['family-name']['value']
        session[:orcid][:info][:name] = "#{given_name} #{family_name}"
      rescue
      end
    end
  end

  def signed_in?
    if session[:orcid].nil?
      false
    else
      !expired_session?
    end
  end

  # Returns true if there is a session and it has expired, or false if the
  # session has not expired or if there is no session.
  def expired_session?
    if session[:orcid].nil?
      false
    else
      creds = session[:orcid]['credentials']
      creds['expires'] && creds['expires_at'] <= Time.now.to_i
    end
  end

  def sign_in_id
    session[:orcid][:uid]
  end

  def user_display
    if signed_in?
      session[:orcid][:info][:name] || session[:orcid][:uid]
    end
  end

  def session_info
    session[:orcid]
  end

  def after_signin_redirect
    redirect_to = session[:after_signin_redirect] || '/'
    session.delete :after_signin_redirect
    redirect_to
  end

  def set_after_signin_redirect redirect_to
    session[:after_signin_redirect] = redirect_to
  end
end



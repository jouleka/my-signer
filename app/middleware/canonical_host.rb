# frozen_string_literal: true

# Redirects www.mysigner.dev -> mysigner.dev to prevent duplicate content in search engines.
class CanonicalHost
  CANONICAL_HOST = "mysigner.dev"

  def initialize(app)
    @app = app
  end

  def call(env)
    request = Rack::Request.new(env)

    if request.host == "www.#{CANONICAL_HOST}"
      location = "#{request.scheme}://#{CANONICAL_HOST}#{request.fullpath}"
      [ 301, { "Location" => location, "Content-Type" => "text/html" }, [ "Moved Permanently" ] ]
    else
      @app.call(env)
    end
  end
end

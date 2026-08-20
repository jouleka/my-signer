class ApiDocsController < ApplicationController
  before_action :restrict_to_development
  layout false

  private

  def restrict_to_development
    head :not_found unless Rails.env.development?
  end

  def index
    # Serves the Swagger UI HTML page
    render inline: swagger_ui_html, content_type: "text/html"
  end

  def spec
    # Serves the OpenAPI spec JSON
    spec_file = Rails.root.join("config", "openapi.yml")
    # Use safe_load to avoid arbitrary object instantiation from the YAML.
    # OpenAPI specs commonly use anchors/merge-keys, so aliases are permitted;
    # no custom Ruby classes are needed for a plain OpenAPI document.
    spec_content = YAML.safe_load_file(spec_file, aliases: true)
    render json: spec_content
  end

  def swagger_ui_html
    <<~HTML
      <!DOCTYPE html>
      <html lang="en">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <meta name="description" content="My Signer API Documentation" />
        <title>My Signer API Documentation</title>
        <link rel="stylesheet" href="https://unpkg.com/swagger-ui-dist@5.10.0/swagger-ui.css" />
        <style>
          body {
            margin: 0;
            padding: 0;
          }
          .topbar {
            display: none;
          }
        </style>
      </head>
      <body>
        <div id="swagger-ui"></div>
        <script src="https://unpkg.com/swagger-ui-dist@5.10.0/swagger-ui-bundle.js" crossorigin></script>
        <script>
          window.onload = () => {
            window.ui = SwaggerUIBundle({
              url: '/api/docs/spec.json',
              dom_id: '#swagger-ui',
              deepLinking: true,
              presets: [
                SwaggerUIBundle.presets.apis,
                SwaggerUIBundle.SwaggerUIStandalonePreset
              ],
              layout: "BaseLayout",
              defaultModelsExpandDepth: 1,
              defaultModelExpandDepth: 1,
              docExpansion: "list",
              filter: true,
              tryItOutEnabled: true,
              persistAuthorization: true,
            });
          };
        </script>
      </body>
      </html>
    HTML
  end
end

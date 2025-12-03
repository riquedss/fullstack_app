# Middleware para fazer proxy reverso para o Vite em desenvolvimento
if Rails.env.development?
  require "rack/proxy"

  class ViteProxy < Rack::Proxy
    def perform_request(env)
      request = Rack::Request.new(env)

      # Se for uma requisição de API ou rota do Rails, não faz proxy
      if api_request?(request)
        @app.call(env)
      else
        # Faz proxy para o Vite
        env["HTTP_HOST"] = "localhost:5173"
        super(env)
      end
    end

    def rewrite_env(env)
      request = Rack::Request.new(env)
      env["REQUEST_URI"] = request.fullpath
      env
    end

    private

    def api_request?(request)
      request.path.start_with?("/api") ||
      request.path.start_with?("/login") ||
      request.path.start_with?("/logout") ||
      request.path.start_with?("/logged_in") ||
      request.path.start_with?("/users") ||
      request.path.start_with?("/groups") ||
      request.path.start_with?("/up") ||
      request.path.start_with?("/greetings") ||
      request.path.start_with?("/expenses") ||
      request.path.start_with?("/payments")
    end
  end

  # Adiciona o middleware de proxy antes do ActionDispatch::Static
  Rails.application.config.middleware.insert_before ActionDispatch::Static, ViteProxy, backend: "http://localhost:5173", streaming: false
end

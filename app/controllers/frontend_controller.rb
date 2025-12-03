class FrontendController < ApplicationController
  def index
    render file: Rails.root.join("client", "dist", "index.html"), layout: false
  end
end

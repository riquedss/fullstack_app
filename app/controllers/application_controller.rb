class ApplicationController < ActionController::API
  include ActionController::Cookies

  private

  def current_user
    @current_user ||= User.find_by(id: session[:user_id]) if session[:user_id]
  end

  def authenticate_user!
    unless current_user
      render json: { status: 401, message: "Você precisa estar logado para acessar esta função." }, status: :unauthorized
    end
  end
end

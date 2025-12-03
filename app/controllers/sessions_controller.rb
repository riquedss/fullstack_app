class SessionsController < ApplicationController
  # Permite o uso de cookies de sessão para o login.
  # Em um aplicativo API-only, isso geralmente requer configuração adicional
  # para CSRF ou usar tokens JWT. Para simplificar, estamos usando sessões baseadas em cookies.

  def create
    user = User.find_by(email: params[:email])

    if user&.authenticate(params[:password])
      session[:user_id] = user.id
      render json: { logged_in: true, user: user }
    else
      render json: { logged_in: false, message: "Email ou senha inválidos." }, status: :unauthorized
    end
  end

  def destroy
    session[:user_id] = nil
    render json: { logged_in: false, message: "Logout realizado com sucesso." }
  end

  def logged_in
    if current_user
      render json: { logged_in: true, user: current_user }
    else
      render json: { logged_in: false }
    end
  end

  private

  def current_user
    @current_user ||= User.find_by(id: session[:user_id]) if session[:user_id]
  end
end

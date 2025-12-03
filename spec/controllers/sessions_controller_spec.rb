require 'rails_helper'

RSpec.describe SessionsController, type: :controller do
  describe 'POST #create' do
    let!(:user) { create(:user, email: 'test@example.com') }

    context 'com credenciais válidas' do
      it 'faz login com sucesso' do
        post :create, params: { email: 'test@example.com', password: 'password' }

        expect(response).to have_http_status(:ok)
        expect(JSON.parse(response.body)['logged_in']).to be true
        expect(JSON.parse(response.body)['user']['email']).to eq('test@example.com')
      end

      it 'cria sessão do usuário' do
        post :create, params: { email: 'test@example.com', password: 'password' }

        expect(session[:user_id]).to eq(user.id)
      end
    end

    context 'com credenciais inválidas' do
      it 'retorna erro para email incorreto' do
        post :create, params: { email: 'wrong@example.com', password: 'password' }

        expect(response).to have_http_status(:unauthorized)
        expect(JSON.parse(response.body)['logged_in']).to be false
        expect(JSON.parse(response.body)['message']).to eq('Email ou senha inválidos.')
      end

      it 'retorna erro para senha incorreta' do
        post :create, params: { email: 'test@example.com', password: 'wrongpassword' }

        expect(response).to have_http_status(:unauthorized)
        expect(JSON.parse(response.body)['logged_in']).to be false
      end

      it 'retorna erro para usuário inexistente' do
        post :create, params: { email: 'nonexistent@example.com', password: 'password' }

        expect(response).to have_http_status(:unauthorized)
        expect(JSON.parse(response.body)['logged_in']).to be false
      end

      it 'não cria sessão para credenciais inválidas' do
        post :create, params: { email: 'test@example.com', password: 'wrongpassword' }

        expect(session[:user_id]).to be_nil
      end
    end
  end

  describe 'DELETE #destroy' do
    let!(:user) { create(:user, email: 'test@example.com') }

    context 'com usuário logado' do
      it 'faz logout com sucesso' do
        session[:user_id] = user.id
        delete :destroy

        expect(response).to have_http_status(:ok)
        expect(JSON.parse(response.body)['logged_in']).to be false
        expect(JSON.parse(response.body)['message']).to eq('Logout realizado com sucesso.')
      end

      it 'limpa sessão do usuário' do
        session[:user_id] = user.id
        delete :destroy

        expect(session[:user_id]).to be_nil
      end
    end
  end

  describe 'GET #logged_in' do
    let!(:user) { create(:user, email: 'test@example.com') }

    context 'com usuário logado' do
      before do
        session[:user_id] = user.id
      end

      it 'retorna status logged_in true' do
        get :logged_in

        expect(response).to have_http_status(:ok)
        expect(JSON.parse(response.body)['logged_in']).to be true
      end

      it 'retorna dados do usuário' do
        get :logged_in

        user_response = JSON.parse(response.body)['user']
        expect(user_response['id']).to eq(user.id)
        expect(user_response['email']).to eq('test@example.com')
      end
    end

    context 'sem usuário logado' do
      it 'retorna status logged_in false' do
        get :logged_in

        expect(response).to have_http_status(:ok)
        expect(JSON.parse(response.body)['logged_in']).to be false
      end

      it 'não retorna dados do usuário' do
        get :logged_in

        expect(JSON.parse(response.body)).not_to have_key('user')
      end
    end

    context 'com sessão inválida' do
      before do
        session[:user_id] = 99999
      end

      it 'retorna status logged_in false' do
        get :logged_in

        expect(response).to have_http_status(:ok)
        expect(JSON.parse(response.body)['logged_in']).to be false
      end
    end
  end
end

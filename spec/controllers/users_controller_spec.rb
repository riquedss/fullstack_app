require 'rails_helper'

RSpec.describe UsersController, type: :controller do
  describe 'POST #create' do
    context 'com dados válidos' do
      let(:valid_params) do
        {
          user: {
            name: 'João Silva',
            email: 'joao@example.com',
            password: 'password123',
            password_confirmation: 'password123'
          }
        }
      end

      it 'cria um novo usuário com sucesso' do
        expect {
          post :create, params: valid_params
        }.to change(User, :count).by(1)

        expect(response).to have_http_status(:created)
        expect(JSON.parse(response.body)['user']['name']).to eq('João Silva')
        expect(JSON.parse(response.body)['user']['email']).to eq('joao@example.com')
      end

      it 'inicia sessão do usuário criado' do
        post :create, params: valid_params
        
        expect(session[:user_id]).to eq(User.last.id)
      end

      it 'retorna o usuário criado no response' do
        post :create, params: valid_params
        
        user_response = JSON.parse(response.body)['user']
        expect(user_response).to have_key('id')
        expect(user_response).to have_key('name')
        expect(user_response).to have_key('email')
        # O controller não filtra campos sensíveis automaticamente
        expect(user_response).to have_key('created_at')
        expect(user_response).to have_key('updated_at')
      end
    end

    context 'com dados inválidos' do
      context 'nome em branco' do
        let(:invalid_params) do
          {
            user: {
              name: '',
              email: 'joao@example.com',
              password: 'password123',
              password_confirmation: 'password123'
            }
          }
        end

        it 'retorna 422 Unprocessable Entity' do
          post :create, params: invalid_params
          
          expect(response).to have_http_status(:unprocessable_entity)
          expect(User.count).to eq(0)
        end

        it 'retorna mensagem de erro apropriada' do
          post :create, params: invalid_params
          
          errors = JSON.parse(response.body)['errors']
          expect(errors).to include("Name can't be blank")
        end
      end

      context 'email inválido' do
        let(:invalid_params) do
          {
            user: {
              name: 'João Silva',
              email: 'email-invalido',
              password: 'password123',
              password_confirmation: 'password123'
            }
          }
        end

        it 'retorna 422 Unprocessable Entity' do
          post :create, params: invalid_params
          
          expect(response).to have_http_status(:unprocessable_entity)
          expect(User.count).to eq(0)
        end

        it 'retorna mensagem de erro de email' do
          post :create, params: invalid_params
          
          errors = JSON.parse(response.body)['errors']
          expect(errors).to include(/Email is invalid/)
        end
      end

      context 'email duplicado' do
        let!(:existing_user) { create(:user, email: 'joao@example.com') }
        
        let(:duplicate_params) do
          {
            user: {
              name: 'Outro João',
              email: 'joao@example.com',
              password: 'password123',
              password_confirmation: 'password123'
            }
          }
        end

        it 'retorna 422 Unprocessable Entity' do
          post :create, params: duplicate_params
          
          expect(response).to have_http_status(:unprocessable_entity)
          expect(User.count).to eq(1)
        end

        it 'retorna mensagem de erro de duplicidade' do
          post :create, params: duplicate_params
          
          errors = JSON.parse(response.body)['errors']
          expect(errors).to include(/Email has already been taken/)
        end
      end

      context 'passwords não conferem' do
        let(:mismatch_params) do
          {
            user: {
              name: 'João Silva',
              email: 'joao@example.com',
              password: 'password123',
              password_confirmation: 'password456'
            }
          }
        end

        it 'retorna 422 Unprocessable Entity' do
          post :create, params: mismatch_params
          
          expect(response).to have_http_status(:unprocessable_entity)
          expect(User.count).to eq(0)
        end

        it 'retorna mensagem de erro de confirmação' do
          post :create, params: mismatch_params
          
          errors = JSON.parse(response.body)['errors']
          expect(errors).to include(/Password confirmation doesn't match/)
        end
      end

      context 'campos obrigatórios faltando' do
        let(:incomplete_params) do
          {
            user: {
              name: 'João Silva'
            }
          }
        end

        it 'retorna 422 Unprocessable Entity' do
          post :create, params: incomplete_params
          
          expect(response).to have_http_status(:unprocessable_entity)
          expect(User.count).to eq(0)
        end

        it 'retorna múltiplas mensagens de erro' do
          post :create, params: incomplete_params
          
          errors = JSON.parse(response.body)['errors']
          expect(errors).to include("Email can't be blank")
          expect(errors).to include("Password can't be blank")
        end
      end
    end
  end

  describe 'GET #show' do
    let!(:user) { create(:user, name: 'Test User', email: 'test@example.com') }

    context 'com ID válido' do
      it 'retorna o usuário solicitado' do
        get :show, params: { id: user.id }
        
        expect(response).to have_http_status(:ok)
        user_response = JSON.parse(response.body)['user']
        expect(user_response['id']).to eq(user.id)
        expect(user_response['name']).to eq('Test User')
        expect(user_response['email']).to eq('test@example.com')
      end

      it 'retorna todos os campos do usuário' do
        get :show, params: { id: user.id }
        
        user_response = JSON.parse(response.body)['user']
        expect(user_response).to have_key('id')
        expect(user_response).to have_key('name')
        expect(user_response).to have_key('email')
        expect(user_response).to have_key('created_at')
        expect(user_response).to have_key('updated_at')
      end
    end

    context 'com ID inválido' do
      it 'retorna 404 Not Found para usuário não existente' do
        get :show, params: { id: 99999 }
        
        expect(response).to have_http_status(:not_found)
        expect(JSON.parse(response.body)['message']).to eq('Usuário não encontrado.')
      end

      it 'retorna 404 Not Found para ID nil' do
        # Testa com string vazia em vez de nil para evitar erro de rota
        get :show, params: { id: '' }
        
        expect(response).to have_http_status(:not_found)
        expect(JSON.parse(response.body)['message']).to eq('Usuário não encontrado.')
      end
    end
  end

  describe 'GET #index' do
    let!(:user1) { create(:user, name: 'Henrique', email: 'henrique@example.com') }
    let!(:user2) { create(:user, name: 'Maria', email: 'maria@example.com') }
    let!(:user3) { create(:user, name: 'Pedro', email: 'pedro@example.com') }

    context 'sem autenticação' do
      it 'retorna 401 Unauthorized' do
        get :index, params: {}
        
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'com autenticação' do
      before { session[:user_id] = user1.id }

      context 'sem parâmetro de busca' do
        it 'retorna lista de todos os usuários' do
          get :index, params: {}
          
          expect(response).to have_http_status(:ok)
          users = JSON.parse(response.body)
          expect(users.length).to eq(3)
        end

        it 'retorna apenas campos permitidos' do
          get :index, params: {}
          
          users = JSON.parse(response.body)
          user = users.first
          expect(user).to have_key('id')
          expect(user).to have_key('name')
          expect(user).to have_key('email')
          expect(user).not_to have_key('password_digest')
          expect(user).not_to have_key('created_at')
        end
      end

      context 'com parâmetro de busca' do
        it 'filtra por nome' do
          get :index, params: { search: 'Henrique' }
          
          expect(response).to have_http_status(:ok)
          users = JSON.parse(response.body)
          expect(users.length).to eq(1)
          expect(users.first['name']).to eq('Henrique')
        end

        it 'filtra por email' do
          get :index, params: { search: 'maria' }
          
          expect(response).to have_http_status(:ok)
          users = JSON.parse(response.body)
          expect(users.length).to eq(1)
          expect(users.first['email']).to eq('maria@example.com')
        end

        it 'busca case insensitive' do
          get :index, params: { search: 'henrique' }
          
          expect(response).to have_http_status(:ok)
          users = JSON.parse(response.body)
          expect(users.length).to eq(1)
          expect(users.first['name']).to eq('Henrique')
        end

        it 'retorna lista vazia para busca sem resultados' do
          get :index, params: { search: 'inexistente' }
          
          expect(response).to have_http_status(:ok)
          users = JSON.parse(response.body)
          expect(users.length).to eq(0)
        end
      end

      context 'parâmetro de busca em branco' do
        it 'retorna todos os usuários para busca vazia' do
          get :index, params: { search: '' }
          
          expect(response).to have_http_status(:ok)
          users = JSON.parse(response.body)
          expect(users.length).to eq(3)
        end

        it 'retorna todos os usuários para busca nil' do
          get :index, params: { search: nil }
          
          expect(response).to have_http_status(:ok)
          users = JSON.parse(response.body)
          expect(users.length).to eq(3)
        end
      end
    end
  end
end

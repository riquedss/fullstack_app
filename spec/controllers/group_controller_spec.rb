require 'rails_helper'

RSpec.describe GroupsController, type: :controller do
  let!(:user) { create(:user) }
  let!(:group) { create(:group, creator: user) }

  before do
    session[:user_id] = user.id
  end

  describe 'GET #index' do
    it 'retorna lista de grupos do usuário' do
      get :index

      expect(response).to have_http_status(:ok)
      groups = JSON.parse(response.body)
      expect(groups.length).to be >= 1
      expect(groups.first).to have_key('id')
      expect(groups.first).to have_key('name')
      expect(groups.first).to have_key('creator')
    end

    it 'inclui dados do criador' do
      get :index

      groups = JSON.parse(response.body)
      creator_data = groups.first['creator']
      expect(creator_data['id']).to eq(user.id)
      expect(creator_data['name']).to eq(user.name)
    end
  end

  describe 'GET #show' do
    it 'retorna dados do grupo' do
      get :show, params: { id: group.id }

      expect(response).to have_http_status(:ok)
      group_data = JSON.parse(response.body)
      expect(group_data['id']).to eq(group.id)
      expect(group_data['name']).to eq(group.name)
    end

    it 'retorna membros do grupo' do
      get :show, params: { id: group.id }

      group_data = JSON.parse(response.body)
      expect(group_data).to have_key('members')
      expect(group_data['members']).to be_an(Array)
    end

    it 'retorna memberships do grupo' do
      get :show, params: { id: group.id }

      group_data = JSON.parse(response.body)
      expect(group_data).to have_key('memberships')
      expect(group_data['memberships']).to be_an(Array)
    end

    it 'retorna 404 para grupo inexistente' do
      get :show, params: { id: 99999 }

      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'POST #create' do
    let(:valid_params) do
      {
        group: {
          name: 'Novo Grupo',
          description: 'Descrição do grupo'
        }
      }
    end

    it 'cria novo grupo com sucesso' do
      expect {
        post :create, params: valid_params
      }.to change(Group, :count).by(1)

      expect(response).to have_http_status(:created)
      response_data = JSON.parse(response.body)
      expect(response_data['group']['name']).to eq('Novo Grupo')
    end

    it 'define usuário como criador' do
      post :create, params: valid_params

      new_group = Group.last
      expect(new_group.creator).to eq(user)
    end

    it 'retorna erro para nome em branco' do
      invalid_params = { group: { name: '' } }

      expect {
        post :create, params: invalid_params
      }.not_to change(Group, :count)

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe 'PATCH #update' do
    let(:update_params) do
      {
        id: group.id,
        group: {
          name: 'Grupo Atualizado',
          description: 'Nova descrição'
        }
      }
    end

    it 'atualiza grupo com sucesso' do
      patch :update, params: update_params

      expect(response).to have_http_status(:ok)
      group.reload
      expect(group.name).to eq('Grupo Atualizado')
      expect(group.description).to eq('Nova descrição')
    end

    it 'retorna dados atualizados' do
      patch :update, params: update_params

      response_data = JSON.parse(response.body)
      expect(response_data['group']['name']).to eq('Grupo Atualizado')
    end

    it 'retorna erro para nome em branco' do
      invalid_params = {
        id: group.id,
        group: { name: '' }
      }

      patch :update, params: invalid_params

      expect(response).to have_http_status(:unprocessable_entity)
      group.reload
      expect(group.name).not_to eq('')
    end

    it 'retorna 404 para grupo inexistente' do
      patch :update, params: { id: 99999, group: { name: 'Teste' } }

      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'DELETE #destroy' do
    it 'retorna 404 para grupo inexistente' do
      expect {
        delete :destroy, params: { id: 99999 }
      }.not_to change(Group, :count)

      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'autenticação' do
    before do
      session[:user_id] = nil
    end

    it 'retorna 401 para index sem autenticação' do
      get :index
      expect(response).to have_http_status(:unauthorized)
    end

    it 'retorna 401 para show sem autenticação' do
      get :show, params: { id: group.id }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'retorna 401 para create sem autenticação' do
      post :create, params: { group: { name: 'Teste' } }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'retorna 401 para update sem autenticação' do
      patch :update, params: { id: group.id, group: { name: 'Teste' } }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'retorna 401 para destroy sem autenticação' do
      delete :destroy, params: { id: group.id }
      expect(response).to have_http_status(:unauthorized)
    end
  end
end

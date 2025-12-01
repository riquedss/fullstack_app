# frozen_string_literal: true

require 'rails_helper'

RSpec.describe GroupMembershipsController, type: :controller do
  let!(:group_creator) { create(:user) }
  let!(:new_user) { create(:user) }
  let!(:existing_member) { create(:user) }
  let!(:group) { create(:group, creator: group_creator, users: [group_creator, existing_member]) }

  # Apenas o criador do grupo pode manipular membros
  before { sign_in group_creator }

  describe 'POST #create' do
    context 'Caminho de Sucesso: Adiciona novo usuário' do
      it 'adiciona o novo usuário ao grupo' do
        expect {
          post :create, params: { group_id: group.id, user_id: new_user.id }
        }.to change(GroupMembership, :count).by(1)
        
        expect(response).to have_http_status(:created)
        expect(group.users).to include(new_user)
      end
    end

    context 'Caminho de Falha: Usuário já é membro' do
      it 'retorna status :unprocessable_entity e não adiciona' do
        expect {
          post :create, params: { group_id: group.id, user_id: existing_member.id }
        }.not_to change(GroupMembership, :count)
        
        expect(response).to have_http_status(:unprocessable_entity)
        expect(json['errors']).to include('Este usuário já é membro do grupo.')
      end
    end
    
    context 'Caminho de Falha: Usuário não encontrado' do
      it 'retorna status :not_found' do
        expect {
          post :create, params: { group_id: group.id, user_id: 99999 } # ID inexistente
        }.not_to change(GroupMembership, :count)
        
        expect(response).to have_http_status(:not_found)
        expect(json['errors']).to include('Usuário não encontrado.')
      end
    end
    
    context 'Caminho de Falha: Usuário sem permissão (Não é o criador)' do
      let!(:unauthorized_user) { create(:user) }
      before { sign_in unauthorized_user }
      
      it 'retorna status :forbidden (403)' do
        expect {
          post :create, params: { group_id: group.id, user_id: new_user.id }
        }.not_to change(GroupMembership, :count)
        
        expect(response).to have_http_status(:forbidden)
      end
    end
  end
end
require 'rails_helper'

RSpec.describe GroupMembershipsController, type: :controller do
  let!(:creator) { create(:user) }
  let!(:new_member) { create(:user) }
  let!(:group) { create(:group, creator: creator) }
  let!(:membership) { create(:group_membership, group: group, user: new_member) }

  # Garante que o usuário logado é o criador do grupo (que tem permissão)
  before { session[:user_id] = creator.id }

  # Adiciona o criador como membro do grupo (necessário pelo set_group)


  # --- Shared Examples para falha do set_group (404) ---
  shared_examples 'returns 404 for missing group' do |action, method, params_key|
    it 'retorna 404 Not Found se o grupo não for encontrado (set_group)' do
      # Cria um usuário que não é membro do grupo
      non_member = create(:user)
      session[:user_id] = non_member.id

      # Tenta acessar um grupo inexistente (cobrindo a falha do set_group)
      process action, method: method, params: { group_id: 99999, params_key => 1 }
      expect(response).to have_http_status(:not_found)
      expect(JSON.parse(response.body)['message']).to include('Grupo não encontrado')
    end
  end

  describe 'POST #create' do
    let!(:uninvited_user) { create(:user) }

    include_examples 'returns 404 for missing group', :create, :post, :user_id

    context 'com permissão (criador)' do
      it 'adiciona um novo membro com sucesso' do
        expect {
          post :create, params: { group_id: group.id, user_id: uninvited_user.id }
        }.to change(GroupMembership, :count).by(1)
        expect(response).to have_http_status(:created)
        expect(GroupMembership.last.user).to eq(uninvited_user)
      end

      it 'retorna 422 se o usuário já for membro' do
        post :create, params: { group_id: group.id, user_id: new_member.id }
        expect(response).to have_http_status(:unprocessable_entity)
        expect(JSON.parse(response.body)['errors']).to include('Este usuário já é membro do grupo.')
      end

      it 'retorna 404 se o usuário não for encontrado' do
        post :create, params: { group_id: group.id, user_id: 99999 }
        expect(response).to have_http_status(:not_found)
      end

      it 'retorna 422 se a criação falhar por falha de validação do modelo' do
        # Força o 'save' a retornar false, cobrindo o bloco 'else' no controller
        allow_any_instance_of(GroupMembership).to receive(:save).and_return(false)
        allow_any_instance_of(GroupMembership).to receive_message_chain(:errors, :full_messages).and_return([ 'Erro forçado de validação.' ])

        expect {
          post :create, params: { group_id: group.id, user_id: uninvited_user.id }
        }.not_to change(GroupMembership, :count)

        expect(response).to have_http_status(:unprocessable_entity)
        expect(JSON.parse(response.body)['errors']).to include('Erro forçado de validação.')
      end
    end

    context 'sem permissão (usuário não-criador)' do
      let!(:unauthorized_user) { create(:user) }
      before { session[:user_id] = unauthorized_user.id }
      before { create(:group_membership, group: group, user: unauthorized_user) }

      it 'retorna 403 Forbidden' do
        post :create, params: { group_id: group.id, user_id: uninvited_user.id }
        expect(response).to have_http_status(:forbidden)
        expect(GroupMembership.count).to eq(3) # Nenhuma mudança
      end
    end
  end

  describe 'DELETE #destroy' do
    include_examples 'returns 404 for missing group', :destroy, :delete, :id

    context 'com permissão (criador)' do
      it 'remove um membro com sucesso' do
        expect {
          delete :destroy, params: { group_id: group.id, id: membership.id }
        }.to change(GroupMembership, :count).by(-1)
        expect(response).to have_http_status(:no_content)
      end

      it 'retorna 422 se tentar remover o criador do grupo' do
        creator_membership = group.group_memberships.find_by(user: creator)
        expect {
          delete :destroy, params: { group_id: group.id, id: creator_membership.id }
        }.not_to change(GroupMembership, :count)
        expect(response).to have_http_status(:unprocessable_entity)
        expect(JSON.parse(response.body)['errors']).to include('Não é possível remover o criador do grupo.')
      end

      it 'retorna 404 se a membresia não for encontrada' do
        delete :destroy, params: { group_id: group.id, id: 99999 }
        expect(response).to have_http_status(:not_found)
      end

      it 'retorna 422 se a remoção falhar' do
        # Força o 'destroy' a retornar false, cobrindo o bloco 'else' no controller
        allow_any_instance_of(GroupMembership).to receive(:destroy).and_return(false)
        allow_any_instance_of(GroupMembership).to receive_message_chain(:errors, :full_messages).and_return([ 'Erro forçado de remoção.' ])

        expect {
          delete :destroy, params: { group_id: group.id, id: membership.id }
        }.not_to change(GroupMembership, :count)

        expect(response).to have_http_status(:unprocessable_entity)
        expect(JSON.parse(response.body)['errors']).to include('Erro forçado de remoção.')
      end
    end

    context 'sem permissão (usuário não-criador)' do
      let!(:unauthorized_user) { create(:user) }
      before { session[:user_id] = unauthorized_user.id }
      before { create(:group_membership, group: group, user: unauthorized_user) }

      it 'retorna 403 Forbidden' do
        expect {
          delete :destroy, params: { group_id: group.id, id: membership.id }
        }.not_to change(GroupMembership, :count)
        expect(response).to have_http_status(:forbidden)
      end
    end
  end
end

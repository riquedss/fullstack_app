# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PaymentsController, type: :controller do
  # Cria dados básicos de teste
  let!(:creator) { create(:user) }
  let!(:other_user) { create(:user) }
  let!(:group) { create(:group, creator: creator, users: [creator, other_user]) }
  
  # O pagamento será do creator para o other_user
  let!(:payment) { create(:payment, group: group, payer: creator, receiver: other_user, amount: 50.0) }
  
  # Simula login do criador (o pagador)
  before { sign_in creator }
  
  # Helper para simular login de um usuário que não tem permissão (other_user)
  def sign_in_other_user
    sign_out creator
    sign_in other_user
  end

  describe 'PATCH #update' do
    let(:valid_attributes) { { amount: 75.0, currency: 'EUR' } }

    context 'QUANDO o usuário logado é o pagador (Autorizado)' do
      it 'atualiza o pagamento com sucesso' do
        patch :update, params: { group_id: group.id, id: payment.id, payment: valid_attributes }
        payment.reload
        expect(payment.amount).to eq(75.0)
        expect(response).to have_http_status(:ok)
      end
    end

    context 'QUANDO o usuário logado NÃO é o pagador (Não Autorizado)' do
      before { sign_in_other_user }
      
      it 'retorna status :forbidden (403) e não altera o pagamento' do
        original_amount = payment.amount
        patch :update, params: { group_id: group.id, id: payment.id, payment: valid_attributes }
        payment.reload
        expect(payment.amount).to eq(original_amount) # Não deve mudar
        expect(response).to have_http_status(:forbidden)
        expect(json['message']).to include('Você não tem permissão')
      end
    end
  end
  
  describe 'DELETE #destroy' do
    context 'QUANDO o usuário logado é o pagador (Autorizado)' do
      it 'exclui o pagamento e retorna status :no_content (204)' do
        expect {
          delete :destroy, params: { group_id: group.id, id: payment.id }
        }.to change(Payment, :count).by(-1)
        expect(response).to have_http_status(:no_content)
      end
    end
    
    context 'QUANDO o usuário logado NÃO é o pagador (Não Autorizado)' do
      before { sign_in_other_user }
      
      it 'retorna status :forbidden (403) e não exclui o pagamento' do
        expect {
          delete :destroy, params: { group_id: group.id, id: payment.id }
        }.not_to change(Payment, :count)
        expect(response).to have_http_status(:forbidden)
        expect(json['message']).to include('Você não tem permissão')
      end
    end
  end
end
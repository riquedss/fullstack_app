require 'rails_helper'

RSpec.describe PaymentsController, type: :controller do
  let!(:payer) { create(:user) }
  let!(:receiver) { create(:user) }
  let!(:other_user) { create(:user) }
  # O Factory de Group (create(:group, creator: payer)) geralmente cria a membership para o creator.
  let!(:group) { create(:group, creator: payer) }

  # REMOVIDO: let!(:payer_membership) { create(:group_membership, group: group, user: payer) }
  # O payer já é membro (criador) do grupo. A criação explícita causava o erro de duplicação.
  let!(:receiver_membership) { create(:group_membership, group: group, user: receiver) }

  let!(:payment) { create(:payment, group: group, payer: payer, receiver: receiver, amount: 50.00) }

  # Garante que o usuário logado é o pagador original
  before { session[:user_id] = payer.id }

  # --- Shared Examples ---

  # Testa a falha do before_action :set_group
  shared_examples 'returns 404 for missing group' do |action, method|
    it 'retorna 404 Not Found se o grupo não for encontrado ou inacessível' do
      # Cria um usuário que não é membro do grupo
      non_member = create(:user)
      session[:user_id] = non_member.id

      # Tenta acessar um grupo inexistente
      process action, method: method, params: { group_id: 99999, id: payment.id }
      expect(response).to have_http_status(:not_found)
      # O JSON de erro agora virá do Controller::set_group
      expect(JSON.parse(response.body)['message']).to include('Grupo não encontrado')
    end
  end

  # Testa a falha do before_action :set_payment
  shared_examples 'returns 404 for missing payment' do |action, method|
    it 'retorna 404 Not Found se o pagamento não for encontrado no grupo' do
      process action, method: method, params: { group_id: group.id, id: 99999 }
      expect(response).to have_http_status(:not_found)
      # O JSON de erro agora virá do Controller::set_payment
      expect(JSON.parse(response.body)['message']).to include('Pagamento não encontrado')
    end
  end

  describe 'GET #index' do
    include_examples 'returns 404 for missing group', :index, :get

    it 'retorna uma lista de pagamentos do grupo' do
      get :index, params: { group_id: group.id }
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body).size).to eq(1)
      expect(JSON.parse(response.body).first['amount']).to eq(50.0) # Deve ser float
    end
  end

  describe 'GET #show' do
    include_examples 'returns 404 for missing group', :show, :get
    include_examples 'returns 404 for missing payment', :show, :get

    it 'retorna o pagamento solicitado' do
      get :show, params: { group_id: group.id, id: payment.id }
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)['amount']).to eq(50.0) # Deve ser float
    end
  end

  describe 'POST #create' do
    let(:valid_params) do
      {
        payment: {
          amount: 100.00,
          receiver_id: receiver.id,
          payment_date: Date.today,
          currency: 'BRL'
        }
      }
    end
    let(:invalid_params) do
      {
        payment: {
          amount: -10.00,
          receiver_id: receiver.id,
          currency: 'BRL'
        }
      }
    end

    include_examples 'returns 404 for missing group', :create, :post

    context 'com parâmetros válidos' do
      it 'cria um novo pagamento com sucesso' do
        expect {
          post :create, params: { group_id: group.id }.merge(valid_params)
        }.to change(Payment, :count).by(1)
        expect(response).to have_http_status(:created)
        expect(Payment.last.payer).to eq(payer)
        expect(Payment.last.amount).to eq(100.00)
      end
    end

    context 'com parâmetros inválidos' do
      it 'retorna 422 Unprocessable Entity (falha de validação)' do
        # Força a falha da validação do modelo para cobrir o bloco 'else'
        allow_any_instance_of(Payment).to receive(:save).and_return(false)
        allow_any_instance_of(Payment).to receive_message_chain(:errors, :full_messages).and_return([ 'Amount must be greater than 0' ])

        expect {
          post :create, params: { group_id: group.id }.merge(valid_params)
        }.not_to change(Payment, :count)

        expect(response).to have_http_status(:unprocessable_entity)
        expect(JSON.parse(response.body)['errors']).to include('Amount must be greater than 0')
      end
    end
  end

  describe 'PATCH/PUT #update' do
    let(:new_amount) { 75.00 }
    let(:update_params) { { payment: { amount: new_amount } } }

    # Adiciona other_user ao grupo para que ele possa tentar acessar
    let!(:other_user_membership) { create(:group_membership, group: group, user: other_user) }

    include_examples 'returns 404 for missing group', :update, :patch
    include_examples 'returns 404 for missing payment', :update, :patch

    context 'com permissão (pagador)' do
      it 'atualiza o pagamento com sucesso' do
        patch :update, params: { group_id: group.id, id: payment.id }.merge(update_params)
        payment.reload
        expect(response).to have_http_status(:ok)
        expect(payment.amount).to eq(new_amount)
      end

      it 'retorna 422 Unprocessable Entity se a atualização falhar' do
        # Força a falha do update para cobrir o bloco 'else'
        allow_any_instance_of(Payment).to receive(:update).and_return(false)
        allow_any_instance_of(Payment).to receive_message_chain(:errors, :full_messages).and_return([ 'Erro forçado de validação na atualização.' ])

        patch :update, params: { group_id: group.id, id: payment.id }.merge(update_params)
        expect(response).to have_http_status(:unprocessable_entity)
        expect(JSON.parse(response.body)['errors']).to include('Erro forçado de validação na atualização.')
      end
    end

    context 'sem permissão (não-pagador)' do
      before { session[:user_id] = other_user.id }

      it 'retorna 403 Forbidden' do
        patch :update, params: { group_id: group.id, id: payment.id }.merge(update_params)
        expect(response).to have_http_status(:forbidden)
        expect(JSON.parse(response.body)['message']).to include('Você não tem permissão para atualizar este pagamento.')
      end
    end
  end

  describe 'DELETE #destroy' do
    # Adiciona other_user ao grupo para que ele possa tentar acessar
    let!(:other_user_membership) { create(:group_membership, group: group, user: other_user) }

    include_examples 'returns 404 for missing group', :destroy, :delete
    include_examples 'returns 404 for missing payment', :destroy, :delete

    context 'com permissão (pagador)' do
      it 'exclui o pagamento com sucesso' do
        # Cria um pagamento que será excluído neste bloco
        payment_to_destroy = create(:payment, group: group, payer: payer, receiver: receiver, amount: 10.00)

        expect {
          delete :destroy, params: { group_id: group.id, id: payment_to_destroy.id }
        }.to change(Payment, :count).by(-1)
        expect(response).to have_http_status(:no_content)
      end

      it 'retorna 422 Unprocessable Entity se a exclusão falhar' do
        # Cria um novo pagamento para o destroy
        payment_to_destroy = create(:payment, group: group, payer: payer, receiver: receiver, amount: 10.00)

        # Força a falha do destroy para cobrir o bloco 'else'
        # Usamos allow_any_instance_of para evitar redefinir let!(:payment)
        allow_any_instance_of(Payment).to receive(:destroy).and_return(false)
        allow_any_instance_of(Payment).to receive_message_chain(:errors, :full_messages).and_return([ 'Erro forçado de remoção.' ])

        expect {
          delete :destroy, params: { group_id: group.id, id: payment_to_destroy.id }
        }.not_to change(Payment, :count)

        expect(response).to have_http_status(:unprocessable_entity)
        expect(JSON.parse(response.body)['errors']).to include('Erro forçado de remoção.')
      end
    end

    context 'sem permissão (não-pagador)' do
      before { session[:user_id] = other_user.id }

      it 'retorna 403 Forbidden' do
        expect {
          delete :destroy, params: { group_id: group.id, id: payment.id }
        }.not_to change(Payment, :count)
        expect(response).to have_http_status(:forbidden)
      end
    end
  end
end

require 'rails_helper'

RSpec.describe ExpensesController, type: :controller do
  # Criação de dados base
  let!(:payer) { create(:user) }
  let!(:member1) { create(:user) }
  let!(:member2) { create(:user) }
  let!(:other_user) { create(:user) }
  let!(:group) { create(:group, creator: payer) } # O payer se torna membro aqui (via callback, presumivelmente)
  let!(:expense) do
    create(:expense, group: group, payer: payer, total_amount: 100.00, currency: 'BRL', description: 'Conta do jantar')
  end
  let!(:participant1) { create(:expense_participant, expense: expense, user: member1, amount_owed: 50.00) }
  let!(:participant2) { create(:expense_participant, expense: expense, user: member2, amount_owed: 50.00) }

  # Configurações iniciais
  before do
    session[:user_id] = payer.id
    # Garante que os demais usuários estão no grupo (payer já é membro via callback do grupo)
    create(:group_membership, group: group, user: member1)
    create(:group_membership, group: group, user: member2)
  end

  # Simula a classe SplitRuleEngine para isolar o teste do controller
  before do
    # Este mock será usado em POST #create e PATCH #update para simular a divisão de R$100.00 em 40/60
    allow_any_instance_of(SplitRuleEngine).to receive(:apply_split).and_return(
      member1 => 40.0,
      member2 => 60.0
    )
  end

  # --- Shared Examples ---

  # Testa a falha do before_action :set_group
  shared_examples 'returns 404 for missing group' do |action, method|
    it 'retorna 404 Not Found se o grupo não for encontrado ou inacessível' do
      # Cria um usuário que não é membro do grupo
      non_member = create(:user)
      session[:user_id] = non_member.id

      # Tenta acessar um grupo inexistente
      process action, method: method, params: { group_id: 99999, id: expense.id }
      expect(response).to have_http_status(:not_found)
      expect(JSON.parse(response.body)['message']).to include('Grupo não encontrado')
    end
  end

  # Testa a falha do before_action :set_expense
  shared_examples 'returns 404 for missing expense' do |action, method|
    it 'retorna 404 Not Found se a despesa não for encontrada no grupo' do
      process action, method: method, params: { group_id: group.id, id: 99999 }
      expect(response).to have_http_status(:not_found)
      expect(JSON.parse(response.body)['message']).to include('Despesa não encontrada')
    end
  end

  # --- Testes de Ações CRUD Básicas ---

  describe 'GET #index' do
    include_examples 'returns 404 for missing group', :index, :get

    it 'retorna uma lista de despesas do grupo' do
      get :index, params: { group_id: group.id }
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body).size).to eq(1)
      expect(JSON.parse(response.body).first['description']).to eq('Conta do jantar')
    end
  end

  describe 'GET #show' do
    include_examples 'returns 404 for missing group', :show, :get
    include_examples 'returns 404 for missing expense', :show, :get

    it 'retorna a despesa solicitada' do
      get :show, params: { group_id: group.id, id: expense.id }
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)['description']).to eq('Conta do jantar')
    end
  end

  # --- Testes de POST #create ---

  describe 'POST #create' do
    include_examples 'returns 404 for missing group', :create, :post

    let(:base_valid_params) do
      {
        expense: {
          description: 'Nova Viagem',
          total_amount: 300.00,
          expense_date: Date.today,
          currency: 'EUR'
        }
      }
    end

    context 'Criação com sucesso (Divisão Padrão: Equally)' do
      it 'cria a despesa e os participantes com a divisão padrão (equally)' do
        # Simula a divisão igualmente, já que os params de split não são passados
        # Nota: O mock global retorna 40/60 para 100.00. Para 300.00, o SplitRuleEngine
        # precisaria ser mockado novamente se a lógica fosse realmente testada.
        # No entanto, se queremos testar "equally", simulamos a divisão igualmente:
        allow_any_instance_of(SplitRuleEngine).to receive(:apply_split).and_return(
          member1 => 150.0,
          member2 => 150.0
        )
        expect {
          post :create, params: { group_id: group.id }.merge(base_valid_params)
        }.to change(Expense, :count).by(1).and change(ExpenseParticipant, :count).by(2)

        created_expense = Expense.last
        expect(response).to have_http_status(:created)
        expect(created_expense.total_amount).to eq(300.00)
        expect(created_expense.expense_participants.map(&:amount_owed)).to contain_exactly(150.0, 150.0)
      end
    end

    context 'Criação com sucesso (Divisão por Porcentagens)' do
      let(:percentage_params) do
        base_valid_params.deep_merge(
          expense: {
            splitting_method: 'percentages',
            splitting_params: {
              percentages: {
                member1.id => 40,
                member2.id => 60
              }
            }
          }
        )
      end

      it 'cria despesa e participantes usando o método de porcentagens' do
        # Aqui, o mock global de 40/60 para R$100.00 entra em ação
        # OBS: Se a despesa criada tem 300.00, o mock deveria retornar 120/180.
        # Ajustando a expectativa para o valor mockado de R$100.00 para passar o teste como está configurado.

        # Para que o teste use o total_amount de 300.00 e retorne 120/180 (40% e 60% de 300):
        allow_any_instance_of(SplitRuleEngine).to receive(:apply_split).and_return(
          member1 => 120.0,
          member2 => 180.0
        )

        expect {
          post :create, params: { group_id: group.id }.merge(percentage_params)
        }.to change(Expense, :count).by(1).and change(ExpenseParticipant, :count).by(2)

        created_expense = Expense.last
        expect(response).to have_http_status(:created)

        # Testando os valores reais com base no mock de R$300.00
        expect(created_expense.expense_participants.find_by(user: member1).amount_owed).to eq(120.0)
        expect(created_expense.expense_participants.find_by(user: member2).amount_owed).to eq(180.0)
      end
    end

    context 'Criação com falha de validação da Despesa' do
      it 'retorna 422 e não cria a despesa (cobre o bloco else/rollback)' do
        # Força o save da despesa a falhar
        allow_any_instance_of(Expense).to receive(:save).and_return(false)
        allow_any_instance_of(Expense).to receive_message_chain(:errors, :full_messages).and_return([ 'Total amount não pode ser zero.' ])

        expect {
          post :create, params: { group_id: group.id }.merge(base_valid_params)
        }.not_to change(Expense, :count)

        expect(response).to have_http_status(:unprocessable_entity)
        expect(JSON.parse(response.body)['errors']).to include('Total amount não pode ser zero.')
      end
    end

    context 'Criação com falha de ArgumentError' do
      it 'retorna 422 se o SplitRuleEngine levantar ArgumentError (cobre o rescue ArgumentError)' do
        # Força o SplitRuleEngine a levantar ArgumentError
        allow_any_instance_of(SplitRuleEngine).to receive(:apply_split).and_raise(ArgumentError, 'Dados de divisão inválidos.')

        expect {
          post :create, params: { group_id: group.id }.merge(base_valid_params)
        }.not_to change(Expense, :count)

        expect(response).to have_http_status(:unprocessable_entity)
        expect(JSON.parse(response.body)['errors']).to include('Dados de divisão inválidos.')
      end
    end

    context 'Criação com falha de StandardError' do
      it 'retorna 500 se ocorrer um erro interno (cobre o rescue StandardError)' do
        # Força um erro genérico
        allow(ActiveRecord::Base).to receive(:transaction).and_raise(StandardError, 'Erro de banco de dados inesperado.')

        expect {
          post :create, params: { group_id: group.id }.merge(base_valid_params)
        }.not_to change(Expense, :count)

        expect(response).to have_http_status(:internal_server_error)
        expect(JSON.parse(response.body)['errors']).to include('Ocorreu um erro interno ao processar a despesa.')
      end
    end
  end

  # --- Testes de PATCH #update ---

  describe 'PATCH #update' do
    include_examples 'returns 404 for missing group', :update, :patch
    include_examples 'returns 404 for missing expense', :update, :patch

    let(:update_params) do
      {
        expense: {
          description: 'Jantar Atualizado',
          total_amount: 200.00,
          splitting_method: 'weights',
          splitting_params: {
            weights: {
              member1.id => 1,
              member2.id => 1
            }
          }
        }
      }
    end

    context 'Com permissão (pagador)' do
      it 'atualiza a despesa, apaga e recria participantes (cobre a transação)' do
        # O mock global de 40/60 é usado. Se o total_amount é 200.00, o mock deve ser ajustado para simular 40/60 de 200.00 (80/120)
        allow_any_instance_of(SplitRuleEngine).to receive(:apply_split).and_return(
          member1 => 80.0,
          member2 => 120.0
        )

        original_participant_count = ExpenseParticipant.count

        patch :update, params: { group_id: group.id, id: expense.id }.merge(update_params)
        expense.reload

        expect(response).to have_http_status(:ok)
        expect(expense.description).to eq('Jantar Atualizado')
        expect(expense.total_amount).to eq(200.00)

        # Verifica se os participantes foram recriados (o mock retorna 80/120)
        expect(expense.expense_participants.count).to eq(2)
        expect(expense.expense_participants.map(&:amount_owed)).to contain_exactly(80.0, 120.0)
        # Garante que o número total de participantes não mudou (foram deletados e recriados)
        expect(ExpenseParticipant.count).to eq(original_participant_count)
      end

      it 'retorna 422 se a atualização da despesa falhar (cobre o bloco else/rollback)' do
        # Força a falha do update da despesa
        allow_any_instance_of(Expense).to receive(:update).and_return(false)
        allow_any_instance_of(Expense).to receive_message_chain(:errors, :full_messages).and_return([ 'Não pode ser atualizado.' ])

        patch :update, params: { group_id: group.id, id: expense.id }.merge(update_params)

        expect(response).to have_http_status(:unprocessable_entity)
        expect(JSON.parse(response.body)['errors']).to include('Não pode ser atualizado.')
      end
    end

    context 'Sem permissão (não-pagador)' do
      before { session[:user_id] = other_user.id }
      before { create(:group_membership, group: group, user: other_user) }
      before { expense.update(payer: member1) } # Despesa agora pertence a member1

      it 'retorna 403 Forbidden' do
        patch :update, params: { group_id: group.id, id: expense.id }.merge(update_params)
        expect(response).to have_http_status(:forbidden)
        expect(JSON.parse(response.body)['message']).to include('Você não tem permissão para atualizar esta despesa.')
      end
    end

    context 'Com falha de ArgumentError durante o split' do
      it 'retorna 422 se o SplitRuleEngine levantar ArgumentError (cobre o rescue ArgumentError)' do
        # Força o SplitRuleEngine a levantar ArgumentError
        allow_any_instance_of(SplitRuleEngine).to receive(:apply_split).and_raise(ArgumentError, 'Erro de pesos inválidos.')

        patch :update, params: { group_id: group.id, id: expense.id }.merge(update_params)

        expect(response).to have_http_status(:unprocessable_entity)
        expect(JSON.parse(response.body)['errors']).to include('Erro de pesos inválidos.')
      end
    end
  end

  # --- Testes de DELETE #destroy ---

  describe 'DELETE #destroy' do
    include_examples 'returns 404 for missing group', :destroy, :delete
    include_examples 'returns 404 for missing expense', :destroy, :delete

    context 'Com permissão (pagador)' do
      it 'exclui a despesa com sucesso' do
        expect {
          delete :destroy, params: { group_id: group.id, id: expense.id }
        }.to change(Expense, :count).by(-1)
        expect(response).to have_http_status(:no_content)
      end

      it 'retorna 422 Unprocessable Entity se a exclusão falhar (cobre o bloco else)' do
        # Força a falha do destroy
        allow_any_instance_of(Expense).to receive(:destroy).and_return(false)
        allow_any_instance_of(Expense).to receive_message_chain(:errors, :full_messages).and_return([ 'Não pode ser excluído.' ])

        expect {
          delete :destroy, params: { group_id: group.id, id: expense.id }
        }.not_to change(Expense, :count)

        expect(response).to have_http_status(:unprocessable_entity)
        expect(JSON.parse(response.body)['errors']).to include('Não pode ser excluído.')
      end
    end

    context 'Sem permissão (não-pagador)' do
      before { session[:user_id] = other_user.id }
      before { create(:group_membership, group: group, user: other_user) }
      before { expense.update(payer: member1) } # Despesa agora pertence a member1

      it 'retorna 403 Forbidden' do
        expect {
          delete :destroy, params: { group_id: group.id, id: expense.id }
        }.not_to change(Expense, :count)
        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  # --- Testes de POST #settle ---

  describe 'POST #settle' do
    let!(:expense_to_settle) do
      # member1 deve 40, member2 deve 60 para o payer
      create(:expense, group: group, payer: payer, total_amount: 100.00, currency: 'BRL', description: 'Para quitar')
    end
    let!(:p1) { create(:expense_participant, expense: expense_to_settle, user: member1, amount_owed: 40.00) }
    let!(:p2) { create(:expense_participant, expense: expense_to_settle, user: member2, amount_owed: 60.00) }
    let!(:p3) { create(:expense_participant, expense: expense_to_settle, user: payer, amount_owed: 0.00) } # Payer no participante

    it 'cria pagamentos para participantes que devem e não estão quitados (sucesso)' do
      expect {
        post :settle, params: { group_id: group.id, id: expense_to_settle.id }
      }.to change(Payment, :count).by(2) # member1 paga payer (40), member2 paga payer (60)

      expect(response).to have_http_status(:created)
      payments = JSON.parse(response.body)['payments']
      expect(payments.size).to eq(2)
      expect(payments.map { |p| p['amount'].to_f }).to contain_exactly(40.0, 60.0)
    end

    it 'não cria pagamento para o pagador da despesa (cobre o next if participant.user == expense.payer)' do
      # Verifica se o participante que é o próprio pagador (p3) é ignorado
      expect {
        post :settle, params: { group_id: group.id, id: expense_to_settle.id }
      }.to change(Payment, :count).by(2) # Apenas p1 e p2 criam payments
    end

    it 'retorna 404 se a despesa não for encontrada' do
      post :settle, params: { group_id: group.id, id: 99999 }
      expect(response).to have_http_status(:not_found)
      expect(JSON.parse(response.body)['error']).to include('Despesa não encontrada.')
    end

    it 'evita criar pagamentos duplicados (cobre o next if quitado)' do
      # Cria um pagamento prévio (member1 já quitou)
      create(:payment, group: group, payer: member1, receiver: payer, amount: 40.00)

      expect {
        post :settle, params: { group_id: group.id, id: expense_to_settle.id }
      }.to change(Payment, :count).by(1) # Apenas member2 paga (60)

      payments = JSON.parse(response.body)['payments']
      expect(payments.size).to eq(1)
      expect(payments.first['amount'].to_f).to eq(60.0)
    end

    it 'retorna 422 em caso de erro na transação (cobre o rescue => e)' do
      # Força um erro ao tentar criar um pagamento (ex: validação falha)
      allow_any_instance_of(Payment).to receive(:save!).and_raise(StandardError, 'Erro forçado ao salvar o pagamento.')

      post :settle, params: { group_id: group.id, id: expense_to_settle.id }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)['error']).to include('Erro ao quitar despesa:')
    end
  end

  # --- Testes da Função Privada normalize_splitting_params ---

  describe '#normalize_splitting_params' do
    # Acesso via send para testar métodos privados
    let(:controller_instance) { ExpensesController.new }

    it 'retorna hash vazio se params_hash for nil ou blank (cobre o return {} if params_hash.blank?)' do
      expect(controller_instance.send(:normalize_splitting_params, nil, :equally)).to eq({})
      expect(controller_instance.send(:normalize_splitting_params, {}, :equally)).to eq({})
    end

    it 'converte ActionController::Parameters para Hash se necessário (cobre o params_hash.to_h)' do
      # Simula o ActionController::Parameters permitido
      mock_params = ActionController::Parameters.new({ 'amounts' => { '1' => '50' } })
      allow(mock_params).to receive(:permitted?).and_return(true)

      normalized = controller_instance.send(:normalize_splitting_params, mock_params, :by_fixed_amounts)

      expect(normalized[:amounts]).to eq({ 1 => 50.0 })
    end

    context 'para :by_percentages' do
      it 'normaliza chaves de string para inteiro e valores para float' do
        params = { 'percentages' => { '1' => '40', '2' => '60.5' } }
        normalized = controller_instance.send(:normalize_splitting_params, params, :by_percentages)
        expect(normalized[:percentages]).to eq({ 1 => 40.0, 2 => 60.5 })
      end
    end

    context 'para :by_weights' do
      it 'normaliza chaves de string para inteiro e valores para float' do
        params = { 'weights' => { '10' => '1', '20' => '2.0' } }
        normalized = controller_instance.send(:normalize_splitting_params, params, :by_weights)
        expect(normalized[:weights]).to eq({ 10 => 1.0, 20 => 2.0 })
      end
    end

    context 'para :by_fixed_amounts' do
      it 'normaliza chaves de string para inteiro e valores para float' do
        params = { 'amounts' => { '5' => '12.34', '6' => '50' } }
        normalized = controller_instance.send(:normalize_splitting_params, params, :by_fixed_amounts)
        expect(normalized[:amounts]).to eq({ 5 => 12.34, 6 => 50.0 })
      end
    end

    context 'para outros métodos (:equally)' do
      it 'retorna um hash vazio' do
        params = { 'other_data' => 'ignored' }
        normalized = controller_instance.send(:normalize_splitting_params, params, :equally)
        expect(normalized).to eq({})
      end
    end
  end
end

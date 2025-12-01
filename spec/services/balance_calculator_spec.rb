require 'rails_helper'
require 'bigdecimal'

RSpec.describe BalanceCalculator, type: :service do
  # Configuração básica de usuários (simulação de fábrica)
  let!(:user_a) { create(:user, id: 10, email: 'a@example.com') }
  let!(:user_b) { create(:user, id: 20, email: 'b@example.com') }
  let!(:user_c) { create(:user, id: 30, email: 'c@example.com') }
  let!(:active_members) { [user_a, user_b, user_c] }

  # Mocks de Participantes e Despesas com arredondamento forçado (10.00 / 3)
  let(:p_a) { instance_double('ExpenseParticipant', user: user_a, amount_owed: BigDecimal('3.34')) }
  let(:p_b) { instance_double('ExpenseParticipant', user: user_b, amount_owed: BigDecimal('3.33')) }
  let(:p_c) { instance_double('ExpenseParticipant', user: user_c, amount_owed: BigDecimal('3.33')) }
  let(:expense_1) do
    instance_double(
      'Expense',
      total_amount: BigDecimal('10.00'),
      payer: user_a,
      expense_participants: [p_a, p_b, p_c]
    )
  end

  # Mocks de Pagamentos
  let(:payment_1) do
    instance_double(
      'Payment',
      amount: BigDecimal('1.00'),
      payer: user_b,    # B está pagando
      receiver: user_a # A está recebendo
    )
  end

  # Mock de Grupo (com despesas e pagamentos)
  let(:group) do
    instance_double(
      'Group',
      id: 1,
      active_members: active_members,
      expenses: [expense_1],
      payments: []
    )
  end

  subject { BalanceCalculator.new(group) }

  # --- Testes para #calculate_net_balances ---

  describe '#calculate_net_balances' do
    context 'Apenas com despesas' do
      it 'calcula corretamente o saldo líquido com base em despesas igualmente divididas' do
        # Esperado (Expense 1: A paga 10.00, A deve 3.34, B deve 3.33, C deve 3.33)
        # A: +10.00 - 3.34 = +6.66
        # B: 0.00 - 3.33 = -3.33
        # C: 0.00 - 3.33 = -3.33
        
        net_balances = subject.calculate_net_balances
        
        expect(net_balances[user_a]).to eq(BigDecimal('6.66'))
        expect(net_balances[user_b]).to eq(BigDecimal('-3.33'))
        expect(net_balances[user_c]).to eq(BigDecimal('-3.33'))
        expect(net_balances.values.sum).to eq(BigDecimal('0.00')) # Cobre ensure_total_balance_is_zero (sucesso)
      end
    end

    context 'Com despesas e pagamentos' do
      before do
        allow(group).to receive(:payments).and_return([payment_1])
      end

      it 'ajusta o saldo líquido com base nos pagamentos (B paga A 1.00)' do
        # Saldo Inicial: A: +6.66, B: -3.33, C: -3.33
        # Pagamento (B paga A 1.00):
        # B (pagador): Saldo += 1.00 => -3.33 + 1.00 = -2.33
        # A (recebedor): Saldo -= 1.00 => +6.66 - 1.00 = +5.66
        
        net_balances = subject.calculate_net_balances
        
        expect(net_balances[user_a]).to eq(BigDecimal('5.66'))
        expect(net_balances[user_b]).to eq(BigDecimal('-2.33'))
        expect(net_balances[user_c]).to eq(BigDecimal('-3.33'))
        expect(net_balances.values.sum).to eq(BigDecimal('0.00'))
      end
    end

    context 'Verificação de Arredondamento (ensure_total_balance_is_zero)' do
      it 'ajusta o saldo do primeiro membro quando há uma pequena discrepância total' do
        # Força uma inconsistência na soma (soma 0.02)
        p_a_fail = instance_double('ExpenseParticipant', user: user_a, amount_owed: BigDecimal('3.32'))
        p_b_fail = instance_double('ExpenseParticipant', user: user_b, amount_owed: BigDecimal('3.33'))
        p_c_fail = instance_double('ExpenseParticipant', user: user_c, amount_owed: BigDecimal('3.33'))
        expense_fail = instance_double('Expense', total_amount: BigDecimal('10.00'), payer: user_a, expense_participants: [p_a_fail, p_b_fail, p_c_fail])
        
        allow(group).to receive(:expenses).and_return([expense_fail])
        
        # Saldo antes do ajuste (Soma dos owes é 9.98, não 10.00):
        # A: +10.00 - 3.32 = +6.68
        # B: 0.00 - 3.33 = -3.33
        # C: 0.00 - 3.33 = -3.33
        # Soma total: 6.68 - 3.33 - 3.33 = 0.02 (Discrepância)
        
        net_balances = subject.calculate_net_balances
        
        # O ajuste (-0.02) deve ir para o user_a (o primeiro membro)
        expect(net_balances[user_a]).to eq(BigDecimal('6.66')) # 6.68 - 0.02
        expect(net_balances[user_b]).to eq(BigDecimal('-3.33'))
        expect(net_balances[user_c]).to eq(BigDecimal('-3.33'))
        expect(net_balances.values.sum).to be_within(BigDecimal('0.0001')).of(BigDecimal('0.00'))
      end
    end
  end

  # --- Testes para #calculate_detailed_balances ---

  describe '#calculate_detailed_balances' do
    context 'Apenas com despesas' do
      it 'cria dívidas diretas de cada participante para o pagador' do
        # Expense 1: B deve A 3.33, C deve A 3.33 (A, o pagador, deve a si mesmo 3.34, que é ignorado)
        detailed_balances = subject.calculate_detailed_balances
        
        expect(detailed_balances[user_b][user_a]).to eq(BigDecimal('3.33'))
        expect(detailed_balances[user_c][user_a]).to eq(BigDecimal('3.33'))
        
        # Verifica que não há outras dívidas
        expect(detailed_balances.keys.sort).to eq([user_b, user_c].sort)
        expect(detailed_balances[user_a]).to be_empty # A não deve a ninguém
      end
    end

    context 'Com pagamentos para liquidar dívida existente' do
      before do
        # Dívida Inicial: B deve A 3.33, C deve A 3.33
        # Pagamento: B paga A 1.00
        allow(group).to receive(:payments).and_return([payment_1])
      end

      it 'reduz o montante da dívida direta' do
        # B deve A: 3.33 - 1.00 = 2.33
        # C deve A: 3.33 (inalterado)
        detailed_balances = subject.calculate_detailed_balances
        
        expect(detailed_balances[user_b][user_a]).to eq(BigDecimal('2.33'))
        expect(detailed_balances[user_c][user_a]).to eq(BigDecimal('3.33'))
        
        # Nenhuma dívida reversa deve ser criada
        expect(detailed_balances[user_a]).to be_empty
      end
    end

    context 'Com pagamentos que sobre-liquidam a dívida (cria dívida reversa)' do
      # Cria um cenário simples onde B deve A 3.00, e C deve A 0.00
      let(:p_a_s) { instance_double('ExpenseParticipant', user: user_a, amount_owed: BigDecimal('7.00')) }
      let(:p_b_s) { instance_double('ExpenseParticipant', user: user_b, amount_owed: BigDecimal('3.00')) }
      let(:p_c_s) { instance_double('ExpenseParticipant', user: user_c, amount_owed: BigDecimal('0.00')) }
      let(:expense_s) do
        instance_double(
          'Expense',
          total_amount: BigDecimal('10.00'),
          payer: user_a,
          expense_participants: [p_a_s, p_b_s, p_c_s]
        )
      end

      let(:payment_over) do
        instance_double(
          'Payment',
          amount: BigDecimal('5.00'),
          payer: user_b,    # B está pagando 5.00
          receiver: user_a # A está recebendo
        )
      end
      
      before do
        # B devia A 3.00. B paga A 5.00.
        allow(group).to receive(:expenses).and_return([expense_s])
        allow(group).to receive(:payments).and_return([payment_over])
      end

      it 'zera a dívida original e cria uma dívida reversa para o recebedor' do
        # 1. B deve A: 3.00. Pagamento: 5.00.
        # 2. Dívida B -> A zerada (3.00 liquidado). Sobra: 2.00.
        # 3. Sobra 2.00, então A (recebedor) deve B (pagador) 2.00.
        
        detailed_balances = subject.calculate_detailed_balances
        
        # B não deve mais a A
        expect(detailed_balances[user_b]).to be_empty 
        
        # A deve B 2.00 (dívida reversa)
        expect(detailed_balances[user_a][user_b]).to eq(BigDecimal('2.00'))
        
        # C não deve nada (0.00 foi limpo)
        expect(detailed_balances[user_c]).to be_empty
      end
    end
  end
end
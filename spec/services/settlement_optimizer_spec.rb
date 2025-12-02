require 'rails_helper'
require 'bigdecimal'

RSpec.describe SettlementOptimizer, type: :service do
  let!(:user_a) { create(:user, email: 'a@example.com') }
  let!(:user_b) { create(:user, email: 'b@example.com') }
  let!(:user_c) { create(:user, email: 'c@example.com') }
  let!(:user_d) { create(:user, email: 'd@example.com') }

  describe '#generate_optimized_payments' do
    context 'quando a dívida é simples (A deve a B)' do
      let(:simple_graph) {
        { user_a => { user_b => BigDecimal('100.00') } }
      }

      it 'gera um único pagamento de A para B' do
        optimizer = SettlementOptimizer.new(simple_graph)
        payments = optimizer.generate_optimized_payments

        expect(payments.size).to eq(1)
        expect(payments.first[:payer]).to eq(user_a)
        expect(payments.first[:receiver]).to eq(user_b)
        expect(payments.first[:amount]).to eq(BigDecimal('100.00'))
      end
    end

    context 'quando a dívida pode ser otimizada em cadeia' do
      let(:chain_graph) {
        {
          user_a => { user_b => BigDecimal('100.00') },
          user_b => { user_c => BigDecimal('100.00') }
        }
      }

      it 'gera um único pagamento direto de A para C' do
        optimizer = SettlementOptimizer.new(chain_graph)
        payments = optimizer.generate_optimized_payments
        
        expect(payments.size).to eq(1)
        expect(payments.first[:payer]).to eq(user_a)
        expect(payments.first[:receiver]).to eq(user_c)
        expect(payments.first[:amount]).to eq(BigDecimal('100.00'))
      end
    end

    context 'quando há otimização complexa (múltiplos saldos líquidos)' do
      let(:complex_graph) {
        {
          user_d => { user_a => BigDecimal('10.00') },
          user_c => { user_b => BigDecimal('50.00') },
          user_a => { user_b => BigDecimal('100.00') }
        }
      }

      it 'gera o conjunto mínimo de 3 pagamentos otimizados' do
        optimizer = SettlementOptimizer.new(complex_graph)
        payments = optimizer.generate_optimized_payments

        expect(payments.size).to eq(3) 
        payment_1 = payments.find { |p| p[:payer] == user_a }
        expect(payments.find { |p| p[:payer] == user_a }[:amount]).to eq(BigDecimal('90.00'))
      end
    end

    context 'quando um pagamento é parcial e o restante é reinserido no loop' do
      let(:partial_graph) {
        {
          user_a => { user_b => BigDecimal('150.00') }, # A deve 150
          user_c => { user_b => BigDecimal('100.00') }  # C deve 100
        }
      }

      it 'resolve o maior devedor primeiro e reinicia o loop' do
    
        optimizer = SettlementOptimizer.new(partial_graph)
        payments = optimizer.generate_optimized_payments

        expect(payments.size).to eq(2)
        

        expect(payments.first[:payer]).to eq(user_a)
        expect(payments.first[:receiver]).to eq(user_b)
        expect(payments.first[:amount]).to eq(BigDecimal('150.00'))
       
        
        expect(payments.last[:payer]).to eq(user_c)
        expect(payments.last[:receiver]).to eq(user_b)
        expect(payments.last[:amount]).to eq(BigDecimal('100.00'))
      end
    end

    context 'quando o pagamento é menor que a tolerância' do
      let(:tolerance_graph) {
        { user_a => { user_b => BigDecimal('0.005') } }
      }
      let(:optimizer_tolerance) { SettlementOptimizer.new(tolerance_graph, tolerance: BigDecimal('0.01')) }

      it 'ignora o pagamento e não adiciona nada ao array' do
        payments = optimizer_tolerance.generate_optimized_payments
        expect(payments).to be_empty
      end
    end
  end
end
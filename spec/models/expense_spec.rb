require 'rails_helper'

RSpec.describe Expense, type: :model do
  let(:payer) { create(:user) }
  let(:group) { create(:group) }
  let(:expense) { build(:expense, payer: payer, group: group) }
  let(:expense_participant) { build(:expense_participant, expense: expense, user: payer) }
  let(:expense_participants) { [ expense_participant ] }

  describe 'Validações' do
    it { should validate_presence_of(:description) }
    it { should validate_presence_of(:total_amount) }
    it { should validate_presence_of(:payer) }
    it { should validate_presence_of(:group) }
    it { should validate_presence_of(:expense_date) }
    it { should validate_presence_of(:currency) }

    context 'data de despesa deve ser no passado' do
      it 'sendo no futuro' do
        expense.expense_date = Date.tomorrow

        expense.expense_date_cannot_be_in_the_future

        expect(expense.errors[:expense_date]).to include('não pode ser no futuro')
      end

      it 'sendo no passado' do
        expense.expense_date = Date.yesterday

        expense.expense_date_cannot_be_in_the_future

        expect(expense.errors[:expense_date]).to be_empty
      end
    end

    context 'o valor total ' do
      it 'corresponde aos valores dos participantes.' do
        expense.total_amount = 100
        allow(expense).to receive(:expense_participants).and_return(expense_participants)
        allow(expense_participants).to receive(:sum).and_return(100)

        expense.total_amount_matches_participant_amounts

        expect(expense.errors[:total_amount]).to be_empty
      end

      it 'não corresponde aos valores dos participantes' do
        expense.total_amount = 100
        allow(expense).to receive(:expense_participants).and_return(expense_participants)
        allow(expense_participants).to receive(:sum).and_return(200)

        expense.total_amount_matches_participant_amounts

        expect(expense.errors[:total_amount]).to include('não corresponde à soma das parcelas dos participantes')
      end
    end

    context 'Pagador deve ser membro ativo do grupo' do
      it 'não sendo membro ativo do grupo' do
        allow(group).to receive(:active_members).and_return([])

        expense.payer_must_be_group_member

        expect(expense.errors[:payer]).to include('deve ser um membro ativo do grupo')
      end

      it 'sendo membro ativo do grupo' do
        allow(group).to receive(:active_members).and_return([ payer ])

        expense.payer_must_be_group_member

        expect(expense.errors[:payer]).to be_empty
      end
    end

    context 'Os participantes devem ser membros ativos do grupo.' do
      it 'sendo membro ativo do grupo' do
        allow(expense).to receive(:expense_participants).and_return(expense_participants)
        allow(group).to receive(:active_members).and_return([ payer ])

        expense.participants_must_be_group_members

        expect(expense.errors[:expense_participants]).to be_empty
      end

      it 'não sendo membro ativo do grupo' do
        allow(expense).to receive(:expense_participants).and_return(expense_participants)
        allow(group).to receive(:active_members).and_return([])

        expense.participants_must_be_group_members

        expect(expense.errors[:expense_participants]).to include('inclui um usuário que não é membro ativo do grupo')
      end
    end
  end

  describe 'Associações' do
    it { should belong_to(:payer).class_name('User') }
    it { should belong_to(:group) }
    it { should have_many(:expense_participants) }
  end
end

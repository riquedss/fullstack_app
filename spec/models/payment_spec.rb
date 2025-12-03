require 'rails_helper'

RSpec.describe Payment, type: :model do
  let(:payer) { create(:user) }
  let(:receiver) { create(:user) }
  let(:group) { create(:group) }
  let(:payment) { build(:payment, payer: payer, receiver: receiver, group: group) }

  describe 'Validações' do
    it { should validate_presence_of(:amount) }
    it { should validate_presence_of(:payer) }
    it { should validate_presence_of(:receiver) }
    it { should validate_presence_of(:group) }
    it { should validate_presence_of(:payment_date) }
    it { should validate_presence_of(:currency) }

    context 'data de pagamento deve ser no passado' do
      it 'sendo no futuro' do
        payment.payment_date = Date.tomorrow

        payment.payment_date_cannot_be_in_the_future

        expect(payment.errors[:payment_date]).to include('não pode ser no futuro')
      end

      it 'sendo no passado' do
        payment.payment_date = Date.yesterday

        payment.payment_date_cannot_be_in_the_future

        expect(payment.errors[:payment_date]).to be_empty
      end
    end

    context 'Pagador deve ser diferente do recebedor' do
      it 'sendo o mesmo que o recebedor' do
        payment.payer = receiver

        payment.payer_cannot_be_receiver

        expect(payment.errors[:receiver]).to include('não pode ser o mesmo que o pagador')
      end

      it 'sendo diferente do recebedor' do
        payment.payer_cannot_be_receiver

        expect(payment.errors[:receiver]).to be_empty
      end
    end

    context 'Pagador deve ser membro ativo do grupo' do
      it 'não sendo membro ativo do grupo' do
        allow(group).to receive(:active_members).and_return([])

        payment.payer_must_be_group_member

        expect(payment.errors[:payer]).to include('deve ser um membro ativo do grupo')
      end

      it 'sendo membro ativo do grupo' do
        allow(group).to receive(:active_members).and_return([ payer ])

        payment.payer_must_be_group_member

        expect(payment.errors[:payer]).to be_empty
      end
    end

    context 'Recebedor deve ser membro ativo do grupo' do
      it 'não sendo membro ativo do grupo' do
        allow(group).to receive(:active_members).and_return([])

        payment.receiver_must_be_group_member

        expect(payment.errors[:receiver]).to include('deve ser um membro ativo do grupo')
      end

      it 'sendo membro ativo do grupo' do
        allow(group).to receive(:active_members).and_return([ receiver ])

        payment.receiver_must_be_group_member

        expect(payment.errors[:receiver]).to be_empty
      end
    end
  end

  describe 'Associações' do
    it { should belong_to(:payer).class_name('User') }
    it { should belong_to(:receiver).class_name('User') }
    it { should belong_to(:group) }
  end
end

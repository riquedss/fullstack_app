class PaymentsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_group
  before_action :set_payment, only: [ :show, :update, :destroy ]

  # GET /groups/:group_id/payments
  def index
    @payments = @group.payments.includes(:payer, :receiver)
    render json: @payments.as_json(include: [ :payer, :receiver ])
  end

  # GET /groups/:group_id/payments/:id
  def show
    render json: @payment.as_json(include: [ :payer, :receiver ])
  end

  # POST /groups/:group_id/payments
  def create
    @payment = @group.payments.new(payment_params)
    @payment.payer = current_user # O usuário logado é o pagador por padrão

    if @payment.save
      render json: { status: :created, payment: @payment.as_json(include: [ :payer, :receiver ]) }, status: :created
    else
      render json: { errors: @payment.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # PATCH/PUT /groups/:group_id/payments/:id
  def update
    # Garante que apenas o pagador do pagamento pode atualizá-lo
    unless @payment.payer == current_user
      render json: { message: "Você não tem permissão para atualizar este pagamento." }, status: :forbidden
      return
    end

    if @payment.update(payment_params)
      render json: { status: :ok, payment: @payment.as_json(include: [ :payer, :receiver ]) }
    else
      render json: { errors: @payment.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # DELETE /groups/:group_id/payments/:id
  def destroy
    # Garante que apenas o pagador do pagamento pode excluí-lo
    unless @payment.payer == current_user
      render json: { message: "Você não tem permissão para excluir este pagamento." }, status: :forbidden
      return
    end

    if @payment.destroy
      render json: { status: :no_content, message: "Pagamento excluído com sucesso." }, status: :no_content
    else
      render json: { errors: @payment.errors.full_messages }, status: :unprocessable_entity
    end
  end

  private

  def set_group
    @group = current_user.groups.find_by(id: params[:group_id])
    unless @group
      render json: { message: "Grupo não encontrado ou você não tem acesso a ele." }, status: :not_found
    end
  end

  def set_payment
    @payment = @group.payments.find_by(id: params[:id])
    unless @payment
      render json: { message: "Pagamento não encontrado no grupo especificado." }, status: :not_found
    end
  end

  def payment_params
    params.require(:payment).permit(
      :amount,
      :receiver_id,
      :payment_date,
      :currency
    )
  end
end

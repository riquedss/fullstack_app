class ExpensesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_group
  before_action :set_expense, only: [ :show, :update, :destroy ]

  # GET /groups/:group_id/expenses
  def index
    @expenses = @group.expenses.includes(:payer, expense_participants: :user)
    render json: @expenses.as_json(include: [ :payer, { expense_participants: { include: :user } } ])
  end

  # GET /groups/:group_id/expenses/:id
  def show
    render json: @expense.as_json(include: [ :payer, { expense_participants: { include: :user } } ])
  end

  # POST /groups/:group_id/expenses
  def create
    @expense = @group.expenses.new(expense_params.except(:splitting_method, :splitting_params))
    @expense.payer = current_user # O usuário logado é o pagador por padrão

    # Inicia uma transação para garantir a atomicidade da despesa e seus participantes
    ActiveRecord::Base.transaction do
      if @expense.save
        # Aplica a regra de divisão usando SplitRuleEngine
        # Mapeia os métodos do frontend para os símbolos esperados pelo SplitRuleEngine
        method_mapping = {
          "equally" => :equally,
          "percentages" => :by_percentages,
          "weights" => :by_weights,
          "fixed_amounts" => :by_fixed_amounts
        }
        raw_method = expense_params[:splitting_method] || "equally"
        splitting_method = method_mapping[raw_method] || :equally
        splitting_params = normalize_splitting_params(expense_params[:splitting_params] || {}, splitting_method)

        # Instancia o serviço com a despesa
        split_engine = SplitRuleEngine.new(@expense)
        participant_amounts = split_engine.apply_split(splitting_method, splitting_params)

        # Cria ExpenseParticipants com os montantes calculados
        participant_amounts.each do |user, amount_owed|
          @expense.expense_participants.create!(user: user, amount_owed: amount_owed)
        end
        render json: { status: :created, expense: @expense.as_json(include: [ :payer, { expense_participants: { include: :user } } ]) }, status: :created
      else
        render json: { errors: @expense.errors.full_messages }, status: :unprocessable_entity
        raise ActiveRecord::Rollback # Reverte a transação se a despesa não puder ser salva
      end
    end
  rescue ArgumentError => e
    render json: { errors: [ e.message ] }, status: :unprocessable_entity
  rescue StandardError => e
    Rails.logger.error("Erro ao criar despesa: #{e.message}\n#{e.backtrace.join("\n")}")
    render json: { errors: [ "Ocorreu um erro interno ao processar a despesa." ] }, status: :internal_server_error
  end

  # PATCH/PUT /groups/:group_id/expenses/:id
  def update
    # Garante que apenas o pagador da despesa pode atualizá-la
    unless @expense.payer == current_user
      render json: { message: "Você não tem permissão para atualizar esta despesa." }, status: :forbidden
      return
    end

    ActiveRecord::Base.transaction do
      # Apaga participantes existentes para recriar com a nova lógica de divisão
      @expense.expense_participants.destroy_all

      if @expense.update(expense_params.except(:splitting_method, :splitting_params))
        # Mapeia os métodos do frontend para os símbolos esperados pelo SplitRuleEngine
        method_mapping = {
          "equally" => :equally,
          "percentages" => :by_percentages,
          "weights" => :by_weights,
          "fixed_amounts" => :by_fixed_amounts
        }
        raw_method = expense_params[:splitting_method] || "equally"
        splitting_method = method_mapping[raw_method] || :equally
        splitting_params = normalize_splitting_params(expense_params[:splitting_params] || {}, splitting_method)

        split_engine = SplitRuleEngine.new(@expense)
        participant_amounts = split_engine.apply_split(splitting_method, splitting_params)

        participant_amounts.each do |user, amount_owed|
          @expense.expense_participants.create!(user: user, amount_owed: amount_owed)
        end
        render json: { status: :ok, expense: @expense.as_json(include: [ :payer, { expense_participants: { include: :user } } ]) }
      else
        render json: { errors: @expense.errors.full_messages }, status: :unprocessable_entity
        raise ActiveRecord::Rollback
      end
    end
  rescue ArgumentError => e
    render json: { errors: [ e.message ] }, status: :unprocessable_entity
  rescue StandardError => e
    Rails.logger.error("Erro ao atualizar despesa: #{e.message}\n#{e.backtrace.join("\n")}")
    render json: { errors: [ "Ocorreu um erro interno ao processar a atualização da despesa." ] }, status: :internal_server_error
  end

  # DELETE /groups/:group_id/expenses/:id
  def destroy
    # Garante que apenas o pagador da despesa pode excluí-la
    unless @expense.payer == current_user
      render json: { message: "Você não tem permissão para excluir esta despesa." }, status: :forbidden
      return
    end

    if @expense.destroy
      render json: { status: :no_content, message: "Despesa excluída com sucesso." }, status: :no_content
    else
      render json: { errors: @expense.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # POST /groups/:group_id/expenses/:id/settle
  def settle
    settle_payments = []
    expense = @group.expenses.find_by(id: params[:id])
    return render json: { error: "Despesa não encontrada." }, status: :not_found unless expense

    ActiveRecord::Base.transaction do
      expense.expense_participants.each do |participant|
        next if participant.user == expense.payer # O pagador não tem que quitar a si mesmo
        # Evita criar pagamentos duplicados (verifica se já foi quitada)
        quitado = @group.payments.where(payer_id: participant.user.id, receiver_id: expense.payer.id)
          .where("amount >= ?", participant.amount_owed)
          .exists?
        next if quitado

        payment = @group.payments.create!(
          payer: participant.user,
          receiver: expense.payer,
          amount: participant.amount_owed,
          payment_date: Date.today,
          currency: expense.currency
        )
        settle_payments << payment
      end
    end
    render json: { status: :created, payments: settle_payments }, status: :created
  rescue => e
    render json: { error: "Erro ao quitar despesa: #{e.message}" }, status: :unprocessable_entity
  end

  private

  def set_group
    @group = current_user.groups.find_by(id: params[:group_id])
    unless @group
      render json: { message: "Grupo não encontrado ou você não tem acesso a ele." }, status: :not_found
    end
  end

  def set_expense
    @expense = @group.expenses.find_by(id: params[:id])
    unless @expense
      render json: { message: "Despesa não encontrada no grupo especificado." }, status: :not_found
    end
  end

  def expense_params
    params.require(:expense).permit(
      :description,
      :total_amount,
      :expense_date,
      :currency,
      :splitting_method, # Será usado pelo serviço, não salvo diretamente no modelo
      splitting_params: {} # Parâmetros para o método de divisão (ex: { user_id: percentage }) - aceita hash genérico
    )
  end

  # Normaliza os parâmetros de divisão convertendo chaves de string para inteiro
  # e garantindo que os valores sejam numéricos
  def normalize_splitting_params(params_hash, splitting_method)
    return {} if params_hash.blank?

    # Converte ActionController::Parameters para hash se necessário
    params_hash = params_hash.to_h if params_hash.is_a?(ActionController::Parameters)
    normalized = {}

    case splitting_method
    when :by_percentages
      percentages = params_hash[:percentages] || params_hash["percentages"]
      if percentages.present?
        # Converte chaves de string para inteiro e valores para numérico
        normalized[:percentages] = percentages.to_h.transform_keys(&:to_i).transform_values(&:to_f)
      end
    when :by_weights
      weights = params_hash[:weights] || params_hash["weights"]
      if weights.present?
        # Converte chaves de string para inteiro e valores para numérico
        normalized[:weights] = weights.to_h.transform_keys(&:to_i).transform_values(&:to_f)
      end
    when :by_fixed_amounts
      amounts = params_hash[:amounts] || params_hash["amounts"]
      if amounts.present?
        # Converte chaves de string para inteiro e valores para numérico
        normalized[:amounts] = amounts.to_h.transform_keys(&:to_i).transform_values(&:to_f)
      end
    end

    normalized
  end
end

class GroupsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_group, only: [ :show, :update, :destroy, :balances_and_settlements ]

  # GET /groups
  def index
    @groups = current_user.groups.includes(:creator)
    render json: @groups.as_json(include: :creator)
  end

  # GET /groups/:id
  def show
    # Retorna o grupo com membros e seus memberships completos
    group_data = @group.as_json(include: [ :creator ])
    memberships_data = @group.group_memberships.includes(:user).map do |membership|
      {
        id: membership.id,
        user: membership.user.as_json(only: [ :id, :name, :email ]),
        status: membership.status,
        joined_at: membership.joined_at
      }
    end
    group_data["memberships"] = memberships_data

    # Inclui o status de cada membro baseado no membership
    members_with_status = @group.members.includes(:group_memberships).map do |member|
      membership = @group.group_memberships.find_by(user: member)
      member.as_json(only: [ :id, :name, :email ]).merge(
        status: membership&.status || "active"
      )
    end
    group_data["members"] = members_with_status

    render json: group_data
  end

  # GET /groups/:group_id/balances_and_settlements
  def balances_and_settlements
    net_balances = BalanceCalculator.new(@group).calculate_net_balances
    detailed_balances = BalanceCalculator.new(@group).calculate_detailed_balances

    aggregated_debt_graph = BalanceAggregator.new(net_balances, detailed_balances).aggregate_balances
    simplified_debt_graph = TransactionSimplifier.new(aggregated_debt_graph).simplify_transactions
    optimized_payments = SettlementOptimizer.new(simplified_debt_graph).generate_optimized_payments

    # Convertendo os balanços e pagamentos para um formato JSON mais amigável
    formatted_net_balances = net_balances.map do |user, amount|
      { user: user.as_json(only: [ :id, :name ]), amount: amount.to_s }
    end

    formatted_detailed_balances = detailed_balances.map do |debtor, creditors_hash|
      {
        debtor: debtor.as_json(only: [ :id, :name ]),
        creditors: creditors_hash.map { |creditor, amount| { user: creditor.as_json(only: [ :id, :name ]), amount: amount.to_s } }
      }
    end

    formatted_optimized_payments = optimized_payments.map do |payment|
      {
        payer: payment[:payer].as_json(only: [ :id, :name ]),
        receiver: payment[:receiver].as_json(only: [ :id, :name ]),
        amount: payment[:amount].to_s
      }
    end

    render json: {
      net_balances: formatted_net_balances,
      detailed_balances: formatted_detailed_balances, # Adicionado para debug/visualização
      optimized_payments: formatted_optimized_payments
    }
  rescue StandardError => e
    Rails.logger.error("Erro ao calcular balanços e liquidações para o grupo #{@group.id}: #{e.message}\n#{e.backtrace.join("\n")}")
    render json: { errors: [ "Ocorreu um erro ao calcular balanços e liquidações." ] }, status: :internal_server_error
  end

  # POST /groups
  def create
    @group = current_user.created_groups.new(group_params)

    if @group.save
      # Adiciona o criador como membro ativo do grupo automaticamente
      @group.group_memberships.create!(user: current_user, status: "active", joined_at: Time.current)
      render json: { status: :created, group: @group.as_json(include: :creator) }, status: :created
    else
      render json: { errors: @group.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # PATCH/PUT /groups/:id
  def update
    # Garante que apenas o criador ou admins do grupo podem atualizar
    if @group.creator == current_user # Ou adicionar lógica de admin/permissão
      if @group.update(group_params)
        render json: { status: :ok, group: @group.as_json(include: :creator) }
      else
        render json: { errors: @group.errors.full_messages }, status: :unprocessable_entity
      end
    else
      render json: { message: "Você não tem permissão para atualizar este grupo." }, status: :forbidden
    end
  end

  # DELETE /groups/:id
  def destroy
    # Garante que apenas o criador ou admins do grupo podem excluir
    if @group.creator == current_user # Ou adicionar lógica de admin/permissão
      @group.destroy
      render json: { status: :no_content, message: "Grupo excluído com sucesso." }, status: :no_content
    else
      render json: { message: "Você não tem permissão para excluir este grupo." }, status: :forbidden
    end
  end

  private

  def set_group
    @group = current_user.groups.find_by(id: params[:id]) # Garante que o usuário logado só acesse seus próprios grupos
    unless @group
      render json: { message: "Grupo não encontrado ou você não tem acesso a ele." }, status: :not_found
    end
  end

  def group_params
    params.require(:group).permit(:name, :description, :group_type)
  end
end

class GroupMembershipsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_group

  # POST /groups/:group_id/group_memberships
  def create
    # Verifica se o usuário tem permissão para adicionar membros (criador do grupo)
    unless @group.creator == current_user
      render json: { message: "Você não tem permissão para adicionar membros a este grupo." }, status: :forbidden
      return
    end

    user = User.find_by(id: params[:user_id])
    unless user
      render json: { errors: [ "Usuário não encontrado." ] }, status: :not_found
      return
    end

    # Verifica se o usuário já é membro do grupo
    if @group.group_memberships.exists?(user: user)
      render json: { errors: [ "Este usuário já é membro do grupo." ] }, status: :unprocessable_entity
      return
    end

    membership = @group.group_memberships.new(
      user: user,
      status: "active",
      joined_at: Time.current
    )

    if membership.save
      render json: { status: :created, membership: membership.as_json(include: :user) }, status: :created
    else
      render json: { errors: membership.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # DELETE /groups/:group_id/group_memberships/:id
  def destroy
    # Verifica se o usuário tem permissão para remover membros (criador do grupo)
    unless @group.creator == current_user
      render json: { message: "Você não tem permissão para remover membros deste grupo." }, status: :forbidden
      return
    end

    membership = @group.group_memberships.find_by(id: params[:id])
    unless membership
      render json: { message: "Membresia não encontrada." }, status: :not_found
      return
    end

    # Não permite remover o criador do grupo
    if membership.user == @group.creator
      render json: { errors: [ "Não é possível remover o criador do grupo." ] }, status: :unprocessable_entity
      return
    end

    if membership.destroy
      render json: { status: :no_content, message: "Membro removido com sucesso." }, status: :no_content
    else
      render json: { errors: membership.errors.full_messages }, status: :unprocessable_entity
    end
  end

  private

  def set_group
    @group = current_user.groups.find_by(id: params[:group_id])
    unless @group
      render json: { message: "Grupo não encontrado ou você não tem acesso a ele." }, status: :not_found
    end
  end
end

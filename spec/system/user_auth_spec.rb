require 'rails_helper'

RSpec.describe 'User Auth', type: :system do
  it 'permite que um visitante crie uma conta', js: true do
    visit '/'

    expect(page).to have_content('Bem-vindo ao Sistema de Divisão de Contas!', wait: 10)

    find('.toggle-auth-mode').click

    fill_in 'Nome', with: 'Fulano'
    fill_in 'Email', with: 'fulano@email.com'
    fill_in 'Senha', with: 'senhasegura', match: :first
    fill_in 'Confirmar Senha', with: 'senhasegura'
    click_button 'Registrar'

    expect(page).to have_content('Bem-vindo, Fulano!')
  end

  it 'permite que um usuário faça login', js: true do
    create(:user, email: 'fulano1@email.com', name: 'Fulano')

    visit '/'

    fill_in 'Email', with: 'fulano1@email.com'
    fill_in 'Senha', with: 'password'
    click_button 'Entrar'

    expect(page).to have_content('Bem-vindo, Fulano!')
  end
end

// fullstack_app/client/src/components/expenses/ExpenseList.tsx
import React from 'react';

interface User {
  id: number;
  name: string;
}

interface ExpenseParticipant {
  id: number;
  user: User;
  amount_owed: string;
}

interface Expense {
  id: number;
  description: string;
  total_amount: string;
  payer: User;
  expense_date: string;
  currency: string;
  expense_participants: ExpenseParticipant[];
}

interface ExpenseListProps {
  expenses: Expense[];
  onEditExpense: (expense: Expense) => void;
  onDeleteExpense: (expenseId: number) => void;
}

const ExpenseList: React.FC<ExpenseListProps> = ({ expenses, onEditExpense, onDeleteExpense }) => {
  if (!expenses || expenses.length === 0) {
    return <p>Nenhuma despesa registrada neste grupo ainda.</p>;
  }

  return (
    <div className="expense-list">
      <h3>Despesas do Grupo</h3>
      {expenses.map(expense => (
        <div key={expense.id} className="expense-item">
          <div className="expense-info">
            <h4>{expense.description}</h4>
            <p>Valor Total: {expense.total_amount} {expense.currency}</p>
            <p>Pago por: {expense.payer.name}</p>
            <p>Data: {new Date(expense.expense_date).toLocaleDateString()}</p>
            <div className="expense-participants-details">
              <h5>Participantes:</h5>
              <ul>
                {expense.expense_participants.map(participant => (
                  <li key={participant.id}>
                    {participant.user.name} deve {participant.amount_owed} {expense.currency}
                  </li>
                ))}
              </ul>
            </div>
          </div>
          <div className="expense-actions">
            <button onClick={() => onEditExpense(expense)}>Editar</button>
            <button onClick={() => onDeleteExpense(expense.id)}>Excluir</button>
          </div>
        </div>
      ))}
    </div>
  );
};

export default ExpenseList;

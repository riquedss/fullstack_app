// fullstack_app/client/src/components/groups/GroupDetailsView.tsx
import React, { useState, useEffect, useCallback } from 'react';
import api from '../../services/api';
import ExpenseList from '../expenses/ExpenseList';
import ExpenseForm from '../expenses/ExpenseForm';
import PaymentList from '../payments/PaymentList';
import PaymentForm from '../payments/PaymentForm';
import GroupBalances from './GroupBalances';
import GroupMembersManager from './GroupMembersManager';

interface User {
  id: number;
  name: string;
  email: string;
}

interface Group {
  id: number;
  name: string;
  description: string;
  group_type: string;
  creator: User;
}

interface GroupMember extends User {
  status: string;
}

interface GroupMembership {
  id: number;
  user: User;
  status: string;
  joined_at: string;
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

interface Payment {
  id: number;
  amount: string;
  payer: User;
  receiver: User;
  payment_date: string;
  currency: string;
}

interface NetBalance {
  user: User;
  amount: string;
}

interface DetailedDebt {
  debtor: User;
  creditors: { user: User; amount: string; }[];
}

interface OptimizedPayment {
  payer: User;
  receiver: User;
  amount: string;
}

interface GroupDetailsViewProps {
  group: Group;
  currentUser: User; // Adicionado para PaymentForm
  onBackToList: () => void;
}

const GroupDetailsView: React.FC<GroupDetailsViewProps> = ({ group, currentUser, onBackToList }) => {
  const [expenses, setExpenses] = useState<Expense[]>([]);
  const [payments, setPayments] = useState<Payment[]>([]);
  const [groupMembers, setGroupMembers] = useState<GroupMember[]>([]);
  const [groupMemberships, setGroupMemberships] = useState<GroupMembership[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [isCreatingExpense, setIsCreatingExpense] = useState(false);
  const [editingExpense, setEditingExpense] = useState<Expense | null>(null);
  const [isCreatingPayment, setIsCreatingPayment] = useState(false);
  const [editingPayment, setEditingPayment] = useState<Payment | null>(null);
  const [showBalances, setShowBalances] = useState(false);
  const [showMembersManager, setShowMembersManager] = useState(false);
  const [netBalances, setNetBalances] = useState<NetBalance[]>([]);
  const [detailedBalances, setDetailedBalances] = useState<DetailedDebt[]>([]);
  const [optimizedPayments, setOptimizedPayments] = useState<OptimizedPayment[]>([]);

  const fetchGroupData = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      // Fetch expenses for the group
      const expensesResponse = await api.get<Expense[]>(`/groups/${group.id}/expenses`);
      setExpenses(expensesResponse.data);

      // Fetch payments for the group
      const paymentsResponse = await api.get<Payment[]>(`/groups/${group.id}/payments`);
      setPayments(paymentsResponse.data);

      // Fetch group members and memberships
      const groupDetailsResponse = await api.get<{ group: Group, members: GroupMember[], memberships: GroupMembership[] }>(`/groups/${group.id}`);
      setGroupMembers(groupDetailsResponse.data.members || []);
      setGroupMemberships(groupDetailsResponse.data.memberships || []);

      // Fetch balances and settlements
      const balancesResponse = await api.get<{ 
        net_balances: NetBalance[]; 
        detailed_balances: DetailedDebt[];
        optimized_payments: OptimizedPayment[];
      }>(`/groups/${group.id}/balances_and_settlements`);

      setNetBalances(balancesResponse.data.net_balances);
      setDetailedBalances(balancesResponse.data.detailed_balances);
      setOptimizedPayments(balancesResponse.data.optimized_payments);

    } catch (err: any) {
      console.error('Erro ao carregar dados do grupo', err);
      setError(err.response?.data?.message || 'Erro ao carregar detalhes do grupo.');
    }
    setLoading(false);
  }, [group.id]);

  useEffect(() => {
    fetchGroupData();
  }, [fetchGroupData]);

  const handleExpenseFormSubmit = () => {
    setIsCreatingExpense(false);
    setEditingExpense(null);
    setShowBalances(false);
    setShowMembersManager(false);
    fetchGroupData();
  };

  const handleEditExpense = (expense: Expense) => {
    setEditingExpense(expense);
    setIsCreatingExpense(false);
    setIsCreatingPayment(false);
    setEditingPayment(null);
    setShowBalances(false);
    setShowMembersManager(false);
  };

  const handleDeleteExpense = async (expenseId: number) => {
    if (window.confirm('Tem certeza que deseja excluir esta despesa?')) {
      try {
        await api.delete(`/groups/${group.id}/expenses/${expenseId}`);
        fetchGroupData();
      } catch (err: any) {
        console.error('Erro ao excluir despesa', err);
        setError(err.response?.data?.message || 'Erro ao excluir despesa.');
      }
    }
  };


  const handlePaymentFormSubmit = () => {
    setIsCreatingPayment(false);
    setEditingPayment(null);
    setShowBalances(false);
    setShowMembersManager(false);
    fetchGroupData();
  };

  const handleEditPayment = (payment: Payment) => {
    setEditingPayment(payment);
    setIsCreatingPayment(false);
    setIsCreatingExpense(false);
    setEditingExpense(null);
    setShowBalances(false);
    setShowMembersManager(false);
  };

  const handleDeletePayment = async (paymentId: number) => {
    if (window.confirm('Tem certeza que deseja excluir este pagamento?')) {
      try {
        await api.delete(`/groups/${group.id}/payments/${paymentId}`);
        fetchGroupData();
      } catch (err: any) {
        console.error('Erro ao excluir pagamento', err);
        setError(err.response?.data?.message || 'Erro ao excluir pagamento.');
      }
    }
  };

  const handleShowBalances = () => {
    setIsCreatingExpense(false);
    setEditingExpense(null);
    setIsCreatingPayment(false);
    setEditingPayment(null);
    setShowMembersManager(false);
    setShowBalances(true);
  };

  const handleShowMembersManager = () => {
    setIsCreatingExpense(false);
    setEditingExpense(null);
    setIsCreatingPayment(false);
    setEditingPayment(null);
    setShowBalances(false);
    setShowMembersManager(true);
  };

  const showExpenseForm = isCreatingExpense || editingExpense;
  const showPaymentForm = isCreatingPayment || editingPayment;
  const isCreator = group.creator.id === currentUser.id;

  if (loading) {
    return <p>Carregando detalhes do grupo...</p>;
  }

  if (error) {
    return <p className="error-message">{error}</p>;
  }

  return (
    <div className="group-details-view">
      <header className="group-details-header">
        <button onClick={onBackToList}>&larr; Voltar para Grupos</button>
        <h2>{group.name}</h2>
        <p className="group-description">{group.description}</p>
        <p className="group-type">Tipo: {group.group_type}</p>
      </header>

      <div className="group-actions">
        <button onClick={() => {
          setIsCreatingExpense(true);
          setIsCreatingPayment(false);
          setEditingExpense(null);
          setEditingPayment(null);
          setShowBalances(false);
          setShowMembersManager(false);
        }}>Adicionar Despesa</button>
        <button onClick={() => {
          setIsCreatingPayment(true);
          setIsCreatingExpense(false);
          setEditingPayment(null);
          setEditingExpense(null);
          setShowBalances(false);
          setShowMembersManager(false);
        }}>Adicionar Pagamento</button>
        <button onClick={handleShowBalances}>Ver Balanços e Otimizar Pagamentos</button>
        <button onClick={handleShowMembersManager}>Gerenciar Membros</button>
      </div>

      <main className="group-content">
        {showExpenseForm ? (
          <ExpenseForm
            groupId={group.id}
            groupMembers={groupMembers}
            existingExpense={editingExpense}
            onFormSubmit={handleExpenseFormSubmit}
            onCancel={() => {
              setIsCreatingExpense(false);
              setEditingExpense(null);
            }}
          />
        ) : showPaymentForm ? (
          <PaymentForm
            groupId={group.id}
            groupMembers={groupMembers}
            currentUser={currentUser}
            existingPayment={editingPayment}
            onFormSubmit={handlePaymentFormSubmit}
            onCancel={() => {
              setIsCreatingPayment(false);
              setEditingPayment(null);
            }}
          />
        ) : showBalances ? (
          <GroupBalances
            netBalances={netBalances}
            detailedBalances={detailedBalances}
            optimizedPayments={optimizedPayments}
            currency={group.creator.default_currency || 'BRL'}
          />
        ) : showMembersManager ? (
          <GroupMembersManager
            groupId={group.id}
            currentMemberships={groupMemberships}
            isCreator={isCreator}
            onMembersUpdated={fetchGroupData}
          />
        ) : (
          <>
            <ExpenseList
              expenses={expenses}
              onEditExpense={handleEditExpense}
              onDeleteExpense={handleDeleteExpense}
            />
            <PaymentList
              payments={payments}
              onEditPayment={handleEditPayment}
              onDeletePayment={handleDeletePayment}
            />
          </>
        )}
      </main>
    </div>
  );
};

export default GroupDetailsView;

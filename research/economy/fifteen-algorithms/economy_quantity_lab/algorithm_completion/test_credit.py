import unittest
from copy import deepcopy
from programme_fixtures import credit_case
from world import ProgrammeWorld
from audit_programme import audit
from credit import repay
from test_programme import simulate,served

class CreditTests(unittest.TestCase):
    def test_credit_funds_early_cash_mismatch_but_total_can_fall(self):
        a=simulate(credit_case());b=simulate(credit_case('E_no_credit'))
        early=lambda s:sum(n['consumed'] for n in s.need_history if n['day']<8)
        self.assertGreater(early(a),early(b));self.assertLess(served(a),served(b))
        self.assertEqual(a.loans['loan-1']['remaining'],0);self.assertEqual(a.received_income['Household'],b.received_income['Household'])
    def test_no_goods_credit_does_not_create_food(self):
        s=simulate(credit_case('E_no_goods'));self.assertEqual(served(s),6);self.assertEqual(s.loans['loan-1']['repaid'],72)
    def test_future_income_absent_no_rollover(self):
        s=simulate(credit_case('E_default'));self.assertEqual(len(s.loans),1)
        self.assertEqual(s.loans['loan-1']['status'],'OVERDUE');self.assertGreater(s.loans['loan-1']['remaining'],0)
    def test_interest_and_zero_control_fixed_at_contract(self):
        a=simulate(credit_case('E_interest'));b=simulate(credit_case());self.assertEqual(a.loans['loan-1']['repaid']-b.loans['loan-1']['repaid'],6)
    def test_unfunded_unknown_lender_not_fake_cash(self):
        for name in ('E_unfunded','E_unknown'):
            s=simulate(credit_case(name));self.assertFalse(s.loans)
    def test_duplicate_repayment_and_failed_transfer_atomic(self):
        s=ProgrammeWorld(credit_case());s.step();s.economics.cash.pay('Lender','Household',1)
        repay(s,'loan-1','repay-once',1);before=s.snapshot()
        with self.assertRaises(ValueError):repay(s,'loan-1','repay-once',1)
        self.assertEqual(before,s.snapshot())
        with self.assertRaises(ValueError):repay(s,'loan-1','unfunded-repay',999999)
        self.assertEqual(before,s.snapshot())
    def test_impairment_not_debt_forgiveness(self):
        c=credit_case('E_default');c['credit']['adjustments']=[dict(day=25,loan='loan-1',kind='impair',amount=10)]
        s=simulate(c);self.assertEqual(s.loans['loan-1']['remaining']-s.loans['loan-1']['creditor_carrying_value'],10)
        c['credit']['adjustments'].append(dict(day=27,loan='loan-1',kind='forgive',amount=5));t=simulate(c)
        self.assertEqual(t.loans['loan-1']['remaining'],s.loans['loan-1']['remaining']-5)
    def test_independent_one_sided_lending_corruption(self):
        s=simulate(credit_case());rows=deepcopy(s.trace);r=next(r for r in rows if r['event']=='loan_issued');r['principal']+=1
        with self.assertRaises(ValueError):audit(rows)

if __name__=='__main__':unittest.main()

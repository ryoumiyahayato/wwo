"""Mechanism and cross-layer correctness tests, not implementation snapshots."""
import unittest
from copy import deepcopy
from programme_fixtures import living_case,scenario
from world import ProgrammeWorld
from audit_programme import audit

def simulate(case):
    s=ProgrammeWorld(case)
    for _ in range(case['days']):s.step()
    audit(s.trace)
    return s
def served(s):return sum(n['consumed'] for n in s.need_history)

class HouseholdLaborTests(unittest.TestCase):
    def test_cash_does_not_remove_need(self):
        rich=simulate(scenario('B_substitute'));poor=simulate(scenario('B_income'))
        self.assertEqual(sum(n['required'] for n in rich.need_history),sum(n['required'] for n in poor.need_history))
        self.assertLess(served(poor),served(rich))
    def test_substitution_fixed_basket_boundary(self):
        self.assertGreater(served(simulate(scenario('B_substitute'))),served(simulate(scenario('B_fixed'))))
    def test_quote_price_and_unknown_shop_change_choice(self):
        for name in ('B_price','B_unknown'):
            s=simulate(scenario(name));self.assertFalse(any(r['event']=='accepted' and r['commodity']=='beans' for r in s.trace))
    def test_unmet_daily_food_does_not_accumulate(self):
        s=simulate(scenario('B_shortage'));self.assertEqual({n['required'] for n in s.need_history},{6})
        self.assertEqual(sum(n['unmet'] for n in s.need_history),180-served(s))
    def test_pending_goods_cannot_be_eaten(self):
        s=simulate(scenario('J1_normal'))
        bean_orders={r['order_id'] for r in s.trace if r['event']=='accepted' and r['commodity']=='beans'}
        first_arrival=min(r['day'] for r in s.trace if r['event']=='arrived' and r['order_id'] in bean_orders)
        before=[r for r in s.trace if r['event']=='household_consumed' and r['day']<first_arrival]
        self.assertTrue(all(r['good']=='bread' for r in before))
    def test_current_income_funds_real_consumption(self):
        s=simulate(scenario('J1_normal'));self.assertEqual(served(s),180)
        self.assertGreater(s.received_income['Household'],0);self.assertEqual(sum(c['remaining'] for c in s.wage_claims.values()),0)
    def test_income_close_need_remains(self):
        normal=simulate(scenario('J1_normal'));lost=simulate(scenario('J2_income'))
        self.assertEqual(sum(n['required'] for n in normal.need_history),sum(n['required'] for n in lost.need_history));self.assertLess(served(lost),served(normal))
    def test_unpaid_work_creates_paired_obligation(self):
        s=simulate(scenario('C_unpaid'));self.assertGreater(s.cohort_hours['Household'],0)
        self.assertEqual(s.received_income['Household'],0);self.assertEqual(sum(c['remaining'] for c in s.wage_claims.values()),360)
    def test_known_skill_geography_and_vacancy_constraints(self):
        for name in ('C_unknown','C_skill','C_far'):
            s=simulate(scenario(name));self.assertFalse(s.contracts);self.assertFalse(any(r['event']=='work' for r in s.trace))
        c=living_case(labor=True);c['jobs'][0]['positions']=1;c['jobs'][1]['positions']=0
        s=simulate(c);self.assertEqual(s.contracts['Household']['workers'],1)
    def test_delayed_job_information_not_leaked(self):
        s=simulate(scenario('J6_information'));self.assertFalse(any(r['event']=='work' and r['day']<6 for r in s.trace));self.assertTrue(any(r['event']=='work' and r['day']==6 for r in s.trace))
    def test_absence_labor_not_contract_produces_capacity(self):
        s=simulate(scenario('C_absent'));self.assertTrue(s.contracts)
        self.assertFalse(any(r['event']=='produced' and r['firm']=='Beaner' and r['day']>=3 for r in s.trace))
    def test_repeat_cash_event_and_failed_payment_atomic(self):
        s=ProgrammeWorld(living_case());s.transfer('x','Household','Baker',1,reason='manual')
        before=s.snapshot()
        with self.assertRaises(ValueError):s.transfer('x','Household','Baker',1,reason='manual')
        self.assertEqual(before,s.snapshot())
        with self.assertRaises(ValueError):s.transfer('y','Household','Baker',999999,reason='manual')
        self.assertEqual(before,s.snapshot())
    def test_shared_input_recipes_and_labor_capacity(self):
        c=living_case(labor=False);c['inventory']['Baker']['grain']=3
        for r in c['routes']:
            if r['buyer_id']=='Baker' and r['commodity']=='grain':r['capacity']=0
        s=simulate(c);used=[r['quantity'] for r in s.trace if r['event']=='consumed' and r['firm']=='Baker' and r['day']==1]
        self.assertLessEqual(sum(used),3)
    def test_named_split_population_ownership_account_no_duplication(self):
        c=living_case(split=True,labor=True);s=simulate(c)
        self.assertEqual(sum(h['members'] for h in s.households.values()),3)
        self.assertIn('Ada',s.stock);self.assertIs(s.firms['Ada'].cash_account,s.economics.cash.accounts['Ada'])
        self.assertEqual(sum(s.cohort_hours.values()),180);self.assertGreater(s.received_income['Ada'],0)
        self.assertEqual(sum(n['required'] for n in s.need_history),180)
        original=simulate(living_case(labor=True))
        self.assertEqual(sum(a.balance for hid,a in s.economics.cash.accounts.items() if hid in s.households),original.economics.cash.accounts['Household'].balance)
        for good in s.goods:self.assertEqual(sum(s.stock[h][good] for h in s.households),original.stock['Household'][good])
        self.assertEqual(served(s),served(original))
    def test_original_N4_unchanged_rule_integrates_new_households(self):
        s=simulate(scenario('C_N4'));self.assertTrue(s.economics.refusal_ceiling);self.assertGreater(served(s),0)

class SalesCommitmentProductionTests(unittest.TestCase):
    def test_planner_does_not_consume_sales_reserved_inputs(self):
        s=ProgrammeWorld(living_case(days=1));s.day=1
        s.stock_commitments.reserve(999,'Baker','grain',20,s.stock['Baker']['grain'])
        plan=s.production_plan()
        self.assertEqual(plan['Baker'],{'bread':0,'soap':0})
        s.produce(plan)
        self.assertEqual(s.stock['Baker']['grain'],20)
        self.assertEqual(s.stock_commitments.uncommitted('Baker','grain',20),0)

    def test_later_reservation_rejects_adopted_plan_before_any_input_debit(self):
        s=ProgrammeWorld(living_case(days=1));s.day=1
        plan=s.production_plan()
        s.stock_commitments.reserve(999,'Baker','grain',20,s.stock['Baker']['grain'])
        before=dict(s.stock['Baker'])
        with self.assertRaises(AssertionError): s.produce(plan)
        self.assertEqual(s.stock['Baker'],before)

class IndependentNegativeTests(unittest.TestCase):
    def setUp(self):self.source=simulate(scenario('J1_normal')).trace
    def reject(self,change):
        rows=deepcopy(self.source);change(rows)
        for n,r in enumerate(rows,1):r['seq']=n
        with self.assertRaises((ValueError,KeyError,TypeError)):audit(rows)
    def test_duplicate_payment(self):
        def mutate(rows):
            i=next(i for i,r in enumerate(rows) if r['event']=='cash_transfer');rows.insert(i+1,deepcopy(rows[i]))
        self.reject(mutate)
    def test_wage_without_work(self):
        self.reject(lambda rows:rows.pop(next(i for i,r in enumerate(rows) if r['event']=='work')))
    def test_duplicate_labor_time(self):
        def mutate(rows):next(r for r in rows if r['event']=='work')['hours']=999
        self.reject(mutate)
    def test_consumption_without_owned_goods(self):
        def mutate(rows):next(r for r in rows if r['event']=='household_consumed')['quantity']=999
        self.reject(mutate)
    def test_unknown_offer(self):
        def mutate(rows):next(r for r in rows if r['event']=='visible_offer')['seller']='UNKNOWN'
        self.reject(mutate)
    def test_future_message(self):
        rows=simulate(scenario('J6_information')).trace
        next(r for r in rows if r['event']=='message')['spec']['observed_day']=99
        with self.assertRaises(ValueError):audit(rows)

if __name__=='__main__':unittest.main()

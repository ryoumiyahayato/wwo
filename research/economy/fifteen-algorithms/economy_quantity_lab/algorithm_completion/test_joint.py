import unittest
from copy import deepcopy
from joint_fixtures import joint_case,scaling_case
from programme_fixtures import living_case,asset_case
from world import ProgrammeWorld
from audit_programme import audit

def execute(c):
    s=ProgrammeWorld(c)
    for _ in range(c['days']):s.step()
    audit(s.trace);return s

class JointTests(unittest.TestCase):
    def test_all15_actual_events_and_physical_chain(self):
        s=execute(joint_case());events={r['event'] for r in s.trace}
        self.assertTrue({'work','wage_accrued','cash_transfer','needs','visible_offer','purchase_choice','accepted','dispatched','arrived','payment','produced','consumed','production_plan','request','transport_position','relation_delivery','loan_issued','fx_exchange','financial_message','asset_trade','asset_dividend','household_consumed'}<=events)
        self.assertTrue(any(r['event']=='consumed' and r['firm']=='Baker2' and r['commodity']=='grain' for r in s.trace))
        self.assertTrue(any(r['event']=='produced' and r['firm']=='Farm' and r['commodity']=='grain' for r in s.trace))
        self.assertTrue(any(r['event']=='request' and r['buyer_id']=='Baker2' and r['supplier_id']=='Farm' for r in s.trace))
        self.assertTrue(any(r['event']=='cash_transfer' and r['reason']=='loan_repayment' for r in s.trace))
    def test_integrated_boundaries_and_controls(self):
        normal=execute(joint_case());short=execute(joint_case('J3_joint_shortage'));default=execute(joint_case('J7_joint_default'));fx=execute(joint_case('J8_no_fx'));assets=execute(joint_case('J9_no_asset'))
        total=lambda s:sum(n['consumed'] for n in s.need_history)
        self.assertGreater(total(normal),total(short));self.assertEqual(fx.metrics['fx_events'],0);self.assertEqual(assets.metrics['asset_trades'],0)
        self.assertEqual(default.loans['joint-loan']['status'],'OVERDUE');self.assertGreater(default.loans['joint-loan']['remaining'],0)
    def test_delayed_opportunity_and_inventory_lag(self):
        s=execute(joint_case('J6_joint_information'))
        self.assertFalse(any(r['event']=='employment' and r['actor']=='Ada' and r['day']<6 for r in s.trace))
        self.assertTrue(any(r['event']=='employment' and r['actor']=='Ada' and r['day']==6 for r in s.trace))
        s=execute(joint_case('J5_joint_logistics'));self.assertTrue(any(r['event']=='transit_delay' for r in s.trace))
    def test_named_exact_and_dormant_search(self):
        a=execute(living_case(labor=True));b=execute(living_case(labor=True,split=True))
        for field in ('required','consumed','unmet'):self.assertEqual(sum(n[field] for n in a.need_history),sum(n[field] for n in b.need_history))
        self.assertEqual(sum(a.cohort_hours.values()),sum(b.cohort_hours.values()));self.assertEqual(sum(a.received_income.values()),sum(b.received_income.values()))
        for good in a.goods:self.assertEqual(a.stock['Household'][good],b.stock['Household'][good]+b.stock['Ada'][good])
        self.assertEqual(a.economics.cash.accounts['Household'].balance,b.economics.cash.accounts['Ada'].balance+b.economics.cash.accounts['Household'].balance)
        a=execute(scaling_case(8,named=True));b=execute(scaling_case(8,named=True,dormant=64))
        for key in ('known_candidate_visits','job_candidate_visits','offer_queries','planning_firm_visits'):self.assertEqual(a.metrics[key],b.metrics[key])
    def test_asset_cash_conflict_retained(self):
        s=execute(asset_case('F_asset_low_liquidity'));self.assertEqual(s.metrics['asset_trades'],0)
if __name__=='__main__':unittest.main()

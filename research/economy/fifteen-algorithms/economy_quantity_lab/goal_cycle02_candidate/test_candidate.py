"""New candidate correctness/negative boundaries, no holdout simulation."""
from pathlib import Path
import sys,tempfile,unittest,inspect,json
from copy import deepcopy
sys.path.insert(0,str(Path(__file__).resolve().parent.parent/'goal_cycle02'))
from learning import local_quote,LearningSimulation,VERSION
from pricing import LocalWindow
from fixtures import core
from run_cycle02 import run

def candidate(days=120,enabled=True,unit=1):
    c=core('coal_scarcity','N3','L_BINDING',days);c['economics']['mode']='N4_EXPERIMENTAL';c['economics']['candidate']=VERSION;c['economics']['candidate_enabled']=enabled;c['case_id']='DEVELOPMENT_N4_'+str(days)
    e=c['economics'];e['prices']={k:v*unit for k,v in e['prices'].items()};e['limits']={k:{g:v*unit for g,v in d.items()} for k,d in e['limits'].items()};e['balances']={k:v*unit for k,v in e['balances'].items()};e['terminal_prices']={k:v*unit for k,v in e['terminal_prices'].items()};e['tick']*=unit
    return c

class CandidateTests(unittest.TestCase):
    def short(self,c,trace=True):
        with tempfile.TemporaryDirectory() as t:return run(c,Path(t)/'run',trace=trace)[0]
    def test_local_pure_signature(self):
        self.assertEqual(list(inspect.signature(local_quote).parameters),['current','initial','tick','window','accepted','previous_ceiling','enabled'])
        w=LocalWindow(400,0,0,798,0,16)
        self.assertEqual(local_quote(112,100,1,w,0,400),local_quote(112,100,1,w,0,400))
    def test_real_price_zero_accept_learns(self):
        r=local_quote(112,100,1,LocalWindow(400,0,0,798,0,16),0,400)
        self.assertTrue(r['ceiling_learned']);self.assertEqual(r['refusal_ceiling'],111);self.assertEqual(r['price'],110)
    def test_some_high_bid_acceptance_prevents_low_bid_bound(self):
        r=local_quote(112,100,1,LocalWindow(400,0,0,798,0,16),1,400)
        self.assertFalse(r['ceiling_learned']);self.assertEqual(r['refusal_ceiling'],400)
    def test_cash_physical_or_no_price_does_not_learn(self):
        for w in (LocalWindow(400,0,0,0,798,16),LocalWindow(0,560,318,0,0,16),LocalWindow(400,0,0,798,1,16)):
            r=local_quote(112,100,1,w,0,400);self.assertFalse(r['ceiling_learned'])
    def test_no_information_holds_price_and_memory_first(self):
        r=local_quote(112,100,1,LocalWindow(400,0,0,798,0,0),0,111)
        self.assertEqual((r['price'],r['refusal_ceiling']),(112,111));self.assertFalse(r['ceiling_learned'])
    def test_rate_limit_priority_over_instant_memory(self):
        r=local_quote(200,100,1,LocalWindow(0,560,318,0,0,16),1,100)
        self.assertEqual(r['price'],196);self.assertGreater(r['price'],r['refusal_ceiling'])
    def test_tick_floor_and_integer_validation(self):
        r=local_quote(49,100,1,LocalWindow(400,0,0,1,0,1),0,400);self.assertEqual(r['price'],49);self.assertEqual(r['step'],0)
        for q in (True,-1,1.5):
            with self.assertRaises(ValueError):local_quote(112,100,1,LocalWindow(400,0,0,1,0,1),q,400)
    def test_unit_scaling_pure_and_real(self):
        x=self.short(candidate(unit=1));y=self.short(candidate(unit=10));self.assertEqual(x['physical_sha256'],y['physical_sha256']);self.assertEqual({k:v*10 for k,v in x['prices'].items()},y['prices'])
    def test_trace_toggle_cannot_change_policy(self):
        c=candidate();x=self.short(c);y=self.short(c,False);self.assertEqual(x,y)
    def test_disabled_candidate_is_exact_v1_authority(self):
        x=self.short(candidate(enabled=False));y=self.short(core('coal_scarcity','N3','L_BINDING',120));self.assertEqual(x['economic_sha256'],y['economic_sha256']);self.assertEqual(x['physical_sha256'],y['physical_sha256'])
    def test_one_cash_accounts_and_no_future_information(self):
        a=candidate(days=80);b=deepcopy(a);b['capacity_events']=[dict(day=81,firm_id='B1',commodity='steel',capacity=0)];b['economics']['price_events']=[dict(day=81,seller='A',commodity='coal',price=390)]
        x=self.short(a);y=self.short(b);self.assertEqual(x['economic_sha256'],y['economic_sha256'])
        s=LearningSimulation(a);self.assertTrue(all(n.cash_account is s.economics.cash.accounts[f] for f,n in s.firms.items()))
if __name__=='__main__':unittest.main()

"""Cycle02 correctness checks; model improvements are never assertions."""
import unittest,tempfile,json,sys,inspect
from pathlib import Path
from copy import deepcopy
from causal import CausalSimulation,CausalTrace,StreamObserver,make_case,canonical,FactorialPolicy
from run_cycle02 import run
from fixtures import factorial,core,holdout,formal_manifest
from pricing import update_price,LocalWindow
from causal_audit import audit as causal_audit,records

class Cycle02Tests(unittest.TestCase):
    def short(self,c,trace=True,observer='compact'):
        with tempfile.TemporaryDirectory() as tmp:
            s,_=run(c,Path(tmp)/'run',observer,trace)
            if trace:self.assertEqual(causal_audit(Path(tmp)/'run')['status'],'PASS')
            return s
    def test_trace_cannot_change_authority(self):
        for mode in ('N2','N3'):
            c=make_case(mode=mode,days=60)
            self.assertEqual(self.short(c),self.short(c,False))
    def test_uniform_price_rank_equals_legacy(self):
        for t in ('T_EQUAL_FEASIBLE','T_MIXED_LEAD'):
            a=self.short(factorial('P_UNIFORM','R_LEGACY',t,60));b=self.short(factorial('P_UNIFORM','R_PRICE_FIRST',t,60))
            self.assertEqual(a['physical_sha256'],b['physical_sha256']);self.assertEqual(a['economic_sha256'],b['economic_sha256'])
    def test_heterogeneity_without_price_rank_same_physical(self):
        a=self.short(factorial('P_UNIFORM','R_LEGACY','T_EQUAL_FEASIBLE',60));b=self.short(factorial('P_HETEROGENEOUS','R_LEGACY','T_EQUAL_FEASIBLE',60))
        self.assertEqual(a['physical_sha256'],b['physical_sha256'])
    def test_real_equal_date_competition_exists(self):
        with tempfile.TemporaryDirectory() as tmp:
            c=factorial('P_HETEROGENEOUS','R_PRICE_FIRST','T_EQUAL_FEASIBLE',40);run(c,Path(tmp)/'run');a=causal_audit(Path(tmp)/'run')
            self.assertGreater(a['matched_competitive_opportunities'],0);self.assertGreater(a['price_sensitive_first_round_accepted_needs'],0)
    def test_diagnostics_world_truth_is_separate(self):
        with tempfile.TemporaryDirectory() as tmp:
            c=make_case(days=20);run(c,Path(tmp)/'run')
            for l in records(Path(tmp)/'run/causal.jsonl'):
                r=json.loads(l)
                if r['event']=='decision':
                    for o in r['buyer_visible_information']['offers']:self.assertNotIn('world_diagnostic',o)
    def test_fixed_binding_and_cash_separation(self):
        c=core('normal','N3','L_BINDING',240);s=self.short(c)
        self.assertGreater(s['rejections'].get('PRICE_LIMIT',0),0);self.assertEqual(s['rejections'].get('CASH',0),0)
    def test_future_information_prefix_isolation(self):
        a=make_case(mode='N3',days=60);b=deepcopy(a)
        b['capacity_events']=[dict(day=61,firm_id='B1',commodity='steel',capacity=0)]
        b['route_events']['A>B1:coal']=[dict(first_day=61,last_day=99,capacity=0)]
        b['economics']['price_events']=[dict(day=61,seller='D',commodity='coal',price=360)]
        b['sinks'][0]['demand_intervals']=[[1,60,5],[61,10000,9]]
        x=self.short(a);y=self.short(b);self.assertEqual(x['economic_sha256'],y['economic_sha256'])
    def test_reversed_containers_and_requests(self):
        a=factorial('P_HETEROGENEOUS','R_PRICE_FIRST','T_EQUAL_FEASIBLE',60);b=deepcopy(a)
        b['firms'].reverse();b['routes'].reverse();b['inventory']=dict(reversed(list(b['inventory'].items())));b['sinks'].reverse();b['reverse_requests']=True
        x=self.short(a);y=self.short(b);self.assertEqual(x['economic_sha256'],y['economic_sha256']);self.assertEqual(x['physical_sha256'],y['physical_sha256'])
    def test_observers60(self):
        c=make_case(mode='N3',days=60);x=[self.short(c,observer=m) for m in ('full','compact','off')]
        self.assertEqual(len({s['economic_sha256'] for s in x}),1);self.assertEqual(len({s['physical_sha256'] for s in x}),1);self.assertEqual(len({s['machine_days_inventory'] for s in x}),1)
    def test_price_boundary_and_ticks(self):
        cases=[(400,100,1,LocalWindow(0,10,2,0,0,1),'upper'),(25,100,1,LocalWindow(100,1,0,0,0,1),'lower'),(49,100,1,LocalWindow(100,1,0,0,0,1),'tick'),(100,100,1,LocalWindow(0,10,2,0,0,0),'hold')]
        for price,initial,tick,w,kind in cases:
            r=update_price(price,initial,tick,w)
            if kind=='upper':self.assertTrue(r['upper_hit']);self.assertEqual(r['price'],400)
            if kind=='lower':self.assertTrue(r['lower_hit']);self.assertEqual(r['price'],25)
            if kind=='tick':self.assertEqual(r['step'],0);self.assertEqual(r['price'],49)
            if kind=='hold':self.assertEqual(r['reason'],'NO_NEW_INFORMATION');self.assertEqual(r['price'],100)
    def test_nominal_unit_transform(self):
        a=make_case(mode='N3',days=120);b=make_case(mode='N3',days=120,unit=10)
        x=self.short(a);y=self.short(b);self.assertEqual(x['physical_sha256'],y['physical_sha256']);self.assertEqual({k:v*10 for k,v in x['prices'].items()},y['prices'])
    def test_no_event_day_price_window_reconstruction(self):
        c=core('coal_scarcity','N3','L_BINDING',60);self.short(c)
    def test_frozen_configuration_shapes(self):
        m=formal_manifest();self.assertEqual(len(m['cases']),43)
        self.assertEqual(sum(x['case_id'].startswith('M2') for x in m['cases']),8)
        self.assertEqual(sum(x['case_id'].startswith('M3') for x in m['cases']),12)
        self.assertEqual(sum(x['case_id'].startswith('M4') for x in m['cases']),12)
    def test_holdouts_have_known_equal_and_mixed_leads(self):
        for kind in ('mixed_date_competition','asymmetric_limits_scarcity'):
            c=holdout(kind,'N3',20)
            self.assertTrue(any(len(f['knowledge'].get('coal',[]))>=2 for f in c['firms']))
if __name__=='__main__':unittest.main()

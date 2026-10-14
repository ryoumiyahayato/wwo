import unittest
from copy import deepcopy
from programme_fixtures import currency_case
from world import ProgrammeWorld
from audit_programme import audit
import currency

def execute(name):
    s=ProgrammeWorld(currency_case(name))
    for _ in range(s.case['days']):s.step()
    audit(s.trace);return s

class CurrencyTests(unittest.TestCase):
    def test_trade_and_limits(self):
        a=execute('F_trade');b=execute('F_no_fx');c=execute('F_unknown_fx');d=execute('F_closed')
        self.assertGreater(a.metrics['fx_events'],0)
        self.assertGreater(sum(n['consumed'] for n in a.need_history),sum(n['consumed'] for n in b.need_history))
        for s in (b,c,d):self.assertEqual(s.metrics['fx_events'],0)
        self.assertGreater(a.economics.cash.accounts['Baker2@FOREIGN'].balance,0)
    def test_atomic_exchange_failure_and_duplicate(self):
        c=currency_case();c['economics']['balances']['Ada']=100;s=ProgrammeWorld(c);before=s.snapshot();accounts=dict(s.economics.cash.accounts)
        with self.assertRaises(RuntimeError):currency.exchange(s,'Ada',3,'manual-fx',fail_after=1)
        self.assertEqual(before,s.snapshot());self.assertTrue(all(s.economics.cash.accounts[k] is v for k,v in accounts.items()))
        currency.exchange(s,'Ada',3,'manual-fx')
        with self.assertRaises(ValueError):currency.exchange(s,'Ada',3,'manual-fx')
        self.assertEqual(s.economics.cash.accounts['Ada'].balance,93)
    def test_nominal_units(self):
        a=execute('F_trade');b=execute('F_units_10')
        self.assertEqual(a.stock,b.stock);self.assertEqual(a.need_history,b.need_history)
        self.assertEqual(len(a.orders),len(b.orders))
        for k,v in a.economics.cash.accounts.items():self.assertEqual(v.balance*10,b.economics.cash.accounts[k].balance)
    def test_information_time(self):
        s=execute('F_info');before=[r for r in s.trace if r['day']<7]
        self.assertFalse(any(r['event']=='fx_exchange' for r in before))
        self.assertTrue(any(r['event']=='fx_exchange' and r['actor']=='Ada' for r in s.trace))
        self.assertFalse(any(r['event']=='fx_exchange' and r['actor']=='Household' for r in s.trace))
    def test_rounding_and_one_leg_mutation(self):
        c=currency_case();c['currency'].update(rate_numerator=3,rate_denominator=2);s=ProgrammeWorld(c)
        self.assertEqual(currency.quote(s,3),6)
        a=execute('F_trade');rows=deepcopy(a.trace);next(r for r in rows if r['event']=='fx_exchange')['legs'].pop()
        with self.assertRaisesRegex(ValueError,'exchange legs'):audit(rows)
    def test_cross_currency_payment_rejected(self):
        s=ProgrammeWorld(currency_case());before=s.snapshot()
        with self.assertRaises(ValueError):s.economics.cash.pay('FX','FX@FOREIGN',1)
        self.assertEqual(before,s.snapshot())
if __name__=='__main__':unittest.main()

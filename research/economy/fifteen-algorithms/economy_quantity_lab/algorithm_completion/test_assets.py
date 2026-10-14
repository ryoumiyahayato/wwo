import unittest
from copy import deepcopy
from programme_fixtures import asset_case
from world import ProgrammeWorld
from audit_programme import audit
import assets

def execute(name='F_asset'):
    s=ProgrammeWorld(asset_case(name))
    for _ in range(s.case['days']):s.step()
    audit(s.trace);return s

class AssetTests(unittest.TestCase):
    def test_cash_shares_dividends(self):
        s=execute();self.assertEqual(s.shares['BEAN'],{'Founder':6,'Ada':4});self.assertEqual(s.metrics['asset_trades'],1)
        self.assertGreater(s.metrics['dividend_events'],0);self.assertEqual(s.share_reserved['BEAN']['Founder'],0)
        trade=next(r for r in s.trace if r['event']=='asset_trade');self.assertEqual(trade['cash'],8)
        # Secondary proceeds went to founder, never issuer operating receipts.
        self.assertEqual(trade['seller'],'Founder');self.assertNotEqual(trade['seller'],s.case['assets']['issuers']['BEAN'])
    def test_information_and_cashflow(self):
        for name in ('F_asset_no_info','F_asset_no_cashflow','F_asset_no_funds'):
            s=execute(name);self.assertEqual(s.metrics['asset_trades'],0)
        s=execute();self.assertFalse(any(r['event']=='asset_order' and r['side']=='buy' and r['day']<10 for r in s.trace))
    def test_no_naked_short_or_double_cash(self):
        s=ProgrammeWorld(asset_case());spec=s.case['assets']['orders'][0];assets.place(s,spec)
        bad=dict(spec,id='ask-too-many',quantity=5)
        with self.assertRaises(ValueError):assets.place(s,bad)
        buy=dict(s.case['assets']['orders'][1],quantity=10,limit=10,requires_public_receipts=False);assets.place(s,buy)
        with self.assertRaises(ValueError):s.economics.cash.reserve('Ada',1)
        assets.cancel(s,buy['id']);self.assertEqual(s.economics.cash.accounts['Ada'].reserved,0)
    def test_atomic_delivery(self):
        s=ProgrammeWorld(asset_case());a,b=s.case['assets']['orders'];b=dict(b,requires_public_receipts=False);assets.place(s,a);assets.place(s,b);before=s.snapshot()
        with self.assertRaises(RuntimeError):assets.trade(s,b['id'],a['id'],4,fail_after_cash=True)
        self.assertEqual(before,s.snapshot());assets.trade(s,b['id'],a['id'],4)
        with self.assertRaises(ValueError):assets.trade(s,b['id'],a['id'],4)
    def test_resale_and_future_information_mutations(self):
        s=execute();rows=deepcopy(s.trace);i=next(i for i,r in enumerate(rows) if r['event']=='asset_trade');rows.insert(i+1,deepcopy(rows[i]))
        for n,r in enumerate(rows,1):r['seq']=n
        with self.assertRaisesRegex(ValueError,'duplicate asset'):audit(rows)
        rows=deepcopy(s.trace);next(r for r in rows if r['event']=='financial_message')['message']['observed_day']=999
        with self.assertRaisesRegex(ValueError,'information timing'):audit(rows)
    def test_insufficient_dividend_and_off_control(self):
        s=execute('F_asset_no_cashflow');self.assertEqual(s.metrics['dividend_events'],0)
        s=execute('F_asset_off');self.assertEqual(s.metrics['asset_trades'],0);self.assertEqual(s.shares['BEAN'],{'Founder':10})
    def test_duplicate_partial_trade_and_information_preflight(self):
        s=ProgrammeWorld(asset_case());a,b=s.case['assets']['orders'];assets.place(s,a)
        with self.assertRaises(ValueError):assets.place(s,b)
        b=dict(b,requires_public_receipts=False);assets.place(s,b);assets.trade(s,b['id'],a['id'],1,event_id='partial-once');before=s.snapshot()
        with self.assertRaisesRegex(ValueError,'duplicate asset'):assets.trade(s,b['id'],a['id'],1,event_id='partial-once')
        self.assertEqual(before,s.snapshot())
if __name__=='__main__':unittest.main()

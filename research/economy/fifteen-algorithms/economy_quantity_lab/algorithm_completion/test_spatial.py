"""Shared transport, delayed evidence and past-partner causal boundaries."""
import unittest
from copy import deepcopy
from programme_fixtures import spatial_case,living_case
from world import ProgrammeWorld
from audit_programme import audit
from test_programme import simulate,served

class SpatialTests(unittest.TestCase):
    def test_shared_edge_and_real_carrier_fees(self):
        s=simulate(spatial_case());totals={}
        for r in s.trace:
            if r['event']=='transport_departed':
                for e in r['path']:totals[(r['day'],e)]=totals.get((r['day'],e),0)+r['quantity']
        self.assertTrue(all(q<=s.case['transport']['edges'][e]['capacity'] for (d,e),q in totals.items()))
        self.assertGreater(s.economics.cash.accounts['Transport'].balance,0)
        self.assertEqual(s.economics.cash.accounts['Transport'].balance,sum(r['amount'] for r in s.trace if r['event']=='cash_transfer' and r['reason']=='freight'))
    def test_interruption_delays_and_inventory_buffers(self):
        s=simulate(spatial_case('J5_interruption'));normal=simulate(spatial_case())
        self.assertTrue(any(r['event']=='transit_delay' for r in s.trace));self.assertLess(served(s),served(normal))
        self.assertFalse(any(r['event']=='transport_departed' and 'local' in r['path'] and 8<=r['day']<15 for r in s.trace))
    def test_mid_transit_pause_and_alternative_path(self):
        s=simulate(spatial_case('D_in_transit'));self.assertTrue(any(r['event']=='transit_delay' for r in s.trace))
        self.assertTrue(any(r['event']=='transport_departed' and 'ferry' in r['path'] for r in s.trace))
        a=simulate(spatial_case('D_alternative'));b=simulate(spatial_case('D_no_alternative'));self.assertGreater(served(a),served(b))
    def test_relationship_changes_considered_order_without_cancelling_old_orders(self):
        a=simulate(spatial_case('D_relation'));b=simulate(spatial_case('D_relation_off'))
        def choices(s):return [(r['actor'],r['seller'],r['good']) for r in s.trace if r['event']=='purchase_choice' and r['day']==8]
        self.assertNotEqual(choices(a),choices(b));self.assertTrue(a.relations)
        self.assertTrue(any(r['event']=='purchase_choice' and r.get('prior_delivery_day') is not None for r in a.trace))
    def test_supplier_message_changes_only_recipient_after_delivery(self):
        s=simulate(spatial_case('D_supplier_info'))
        self.assertFalse(any(r['event']=='accepted' and r['commodity']=='beans' and (r['buyer']!='Ada' or r['day']<7) for r in s.trace))
        self.assertTrue(any(r['event']=='accepted' and r['commodity']=='beans' and r['buyer']=='Ada' for r in s.trace))
    def test_freight_and_goods_rollback_share_one_wallet(self):
        c=spatial_case();s=ProgrammeWorld(c);s.day=1;s.edge_remaining={e:v['capacity'] for e,v in s.edges.items()}
        s.economics.cash.pay('Beaner','Ada',10);o=s.quote('Ada','beans','Beaner');route=s.route_index[('Ada','beans','Beaner')]
        before=deepcopy(s.economics.cash.accounts['Ada']);s.economics.failpoint='order'
        with self.assertRaises(RuntimeError):s.economics.accept(route,1,s.route_slots[route].quote(s.day,s.capacity(route,s.day)))
        self.assertEqual(before,s.economics.cash.accounts['Ada']);self.assertFalse(s.orders);self.assertTrue(all(not slots.allocations for slots in s.shared_slots.values()))
    def test_independent_shared_capacity_negative(self):
        s=simulate(spatial_case());rows=deepcopy(s.trace);r=next(r for r in rows if r['event']=='transport_departed');r['quantity']=999
        with self.assertRaises(ValueError):audit(rows)

if __name__=='__main__':unittest.main()

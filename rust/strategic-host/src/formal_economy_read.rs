use super::InitialWorld;
use crate::{
    formal_clock::MINUTES_PER_HOUR,
    formal_ledger::LedgerPayment,
    formal_macro::Shipment,
    transport::operations::{ActiveVehicle, ReservedLeg, Traffic},
};
use std::collections::BTreeSet;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ShipmentStatus {
    Scheduled,
    InTransit,
    Held,
    Delivered,
    LegacyInTransit,
}

pub struct TradeShipment<'a> {
    pub shipment: &'a Shipment,
    pub status: ShipmentStatus,
    /// Last reached station. During movement this is the station behind the vehicle.
    pub at: Option<&'a str>,
    pub arrival_minute: Option<i64>,
    pub load_units: Option<u32>,
    pub goods_payment: Option<LedgerPayment<'a>>,
    /// The ledger entry for the latest carriage. An earlier carriage may have been refunded.
    pub freight_payment: Option<LedgerPayment<'a>>,
    pub refund: Option<LedgerPayment<'a>>,
}

pub struct EconomicTransportFlow<'a> {
    pub from: &'a str,
    pub to: &'a str,
    pub load_units: u32,
}

pub struct SegmentReservation<'a> {
    pub from: &'a str,
    pub to: &'a str,
    pub load_units: u32,
    pub starts: i64,
    pub ends: i64,
    pub moving: bool,
    pub freight: bool,
    /// Only populated when the current player can manage the booked lot.
    pub freight_lot: Option<u64>,
}

pub struct SegmentEconomy<'a> {
    pub from_market: Option<&'a str>,
    pub to_market: Option<&'a str>,
    pub reservations: Vec<SegmentReservation<'a>>,
    pub trade: Vec<TradeShipment<'a>>,
    /// Completed records carry the stored corridor identity.
    pub last_arrivals: Vec<TradeShipment<'a>>,
    pub interrupted_trade: Vec<TradeShipment<'a>>,
}

pub struct FirmMaterialOrder<'a> {
    pub reference: String,
    pub buyer: &'a str,
    pub seller: &'a str,
    pub from: &'a str,
    pub to: &'a str,
    pub requested: i64,
    pub pending: i64,
    pub delivered: i64,
    pub order_day: i64,
    pub delivery_day: Option<i64>,
    pub goods_payment: Option<LedgerPayment<'a>>,
}

impl InitialWorld {
    pub fn transport_vehicle(&self, reservation: u64) -> Option<ActiveVehicle<'_>> {
        self.transport.visible_vehicle(reservation)
    }

    pub fn moving_transport_segments(&self) -> impl Iterator<Item = &str> {
        self.transport.moving_segments()
    }

    pub fn freight_movement_revision(&self) -> u64 {
        self.transport.freight_movement_revision()
    }

    pub fn economic_transport_on(&self, segment: &str) -> impl Iterator<Item = EconomicTransportFlow<'_>> {
        self.transport.reserved_legs(segment)
            .filter(|row| row.moving && carries_freight(row.traffic))
            .map(|row| EconomicTransportFlow {
                from: &row.leg.from,
                to: &row.leg.to,
                load_units: row.load_units,
            })
    }

    pub fn transport_economy(&self, segment: &str) -> Option<SegmentEconomy<'_>> {
        let segment = self.transport.network().segment(segment)?;
        let mut trade_reservations = BTreeSet::new();
        let reservations = self.transport.reserved_legs(&segment.id).map(|row| {
            if row.traffic == Traffic::Trade {
                trade_reservations.insert(row.id);
            }
            self.segment_reservation(row)
        }).collect();

        let mut trade = Vec::new();
        let mut interrupted_trade = Vec::new();
        for shipment in self.macro_economy.shipments() {
            if let Some(carriage) = &shipment.carriage {
                if trade_reservations.contains(&carriage.reservation) {
                    trade.push(self.trade_shipment(shipment, false));
                } else if carriage.held && self.transport.held_leg(carriage.reservation)
                    .is_some_and(|leg| leg.segment_id == segment.id) {
                    interrupted_trade.push(self.trade_shipment(shipment, false));
                }
            } else if shipment.route_id == segment.id {
                trade.push(self.trade_shipment(shipment, false));
            }
        }
        let last_arrivals = self.macro_economy.last_arrivals().iter()
            .filter(|shipment| shipment.route_id == segment.id)
            .map(|shipment| self.trade_shipment(shipment, true))
            .collect();
        Some(SegmentEconomy {
            from_market: self.population_unit_at(&segment.from),
            to_market: self.population_unit_at(&segment.to),
            reservations,
            trade,
            last_arrivals,
            interrupted_trade,
        })
    }

    pub fn trade_shipments(&self) -> impl Iterator<Item = TradeShipment<'_>> {
        self.scoped_trade_shipments(None)
    }

    pub fn trade_market_shipments<'a>(&'a self, unit: &'a str) -> impl Iterator<Item = TradeShipment<'a>> + 'a {
        self.scoped_trade_shipments(Some(unit))
    }

    fn scoped_trade_shipments<'a>(&'a self, unit: Option<&'a str>) -> impl Iterator<Item = TradeShipment<'a>> + 'a {
        let economy = &self.macro_economy;
        economy.last_arrivals().iter().map(|shipment| (shipment, true))
            .chain(economy.shipments().iter().map(|shipment| (shipment, false)))
            .filter(move |(shipment, _)| unit.is_none_or(|unit| shipment.origin == unit || shipment.destination == unit))
            .map(move |(shipment, arrived)| self.trade_shipment(shipment, arrived))
    }

    fn segment_reservation<'a>(&'a self, row: ReservedLeg<'a>) -> SegmentReservation<'a> {
        SegmentReservation {
            from: &row.leg.from,
            to: &row.leg.to,
            load_units: row.load_units,
            starts: row.starts,
            ends: row.ends,
            moving: row.moving,
            freight: carries_freight(row.traffic),
            freight_lot: self.freight_for_reservation(row.id).map(|lot| lot.id),
        }
    }

    fn trade_shipment<'a>(&'a self, shipment: &'a Shipment, arrived: bool) -> TradeShipment<'a> {
        let mut read = TradeShipment {
            shipment,
            status: if arrived { ShipmentStatus::Delivered } else { ShipmentStatus::LegacyInTransit },
            at: None,
            arrival_minute: shipment.arrival_hour.checked_mul(MINUTES_PER_HOUR),
            load_units: None,
            goods_payment: None,
            freight_payment: None,
            refund: None,
        };
        if let Some(carriage) = &shipment.carriage {
            let id = carriage.reservation;
            read.at = self.transport.location(id);
            read.status = if arrived {
                ShipmentStatus::Delivered
            } else if carriage.held {
                ShipmentStatus::Held
            } else if self.transport.moving(id) {
                ShipmentStatus::InTransit
            } else {
                ShipmentStatus::Scheduled
            };
            read.arrival_minute = (read.status != ShipmentStatus::Held).then_some(carriage.arrival_minute);
            read.load_units = carriage.mass_slots.or_else(|| self.transport.plan(id).map(|plan| plan.load_units()));
            read.goods_payment = self.ledger.payment(&format!("goods:{}", shipment.id));
            read.freight_payment = self.ledger.payment(&format!("carriage:{id}"));
            read.refund = self.ledger.payment(&format!("held-refund:{id}"));
        }
        read
    }
}

fn carries_freight(traffic: Traffic) -> bool {
    matches!(traffic, Traffic::Trade | Traffic::PlayerFreight | Traffic::PriorityFreight)
}

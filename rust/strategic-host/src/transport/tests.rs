use super::*;

fn city(id: &str) -> TransportNode {
    TransportNode {
        id: id.into(),
        kind: NodeKind::City,
    }
}

fn rail(id: &str, from: &str, to: &str, minutes: u32) -> TransportSegment {
    TransportSegment {
        id: id.into(),
        from: from.into(),
        to: to.into(),
        mode: TransportMode::Rail,
        bidirectional: true,
        prototype_only: false,
        profile: SegmentProfile {
            travel_minutes: minutes,
            cost_units: 3,
            capacity_units: 10,
            risk_points: 2,
        },
    }
}

fn query(from: &str, to: &str, capacity_units: u32) -> TransportRequest {
    TransportRequest {
        from: from.into(),
        to: to.into(),
        allowed_modes: ModeSet::ALL,
        capacity_units,
    }
}

#[test]
fn reopening_a_shortcut_refreshes_routes_but_an_unrelated_change_preserves_them() {
    let mut network = TransportNetwork::new(
        ["a", "b", "c", "d", "e"].map(city).to_vec(),
        vec![
            rail("ab", "a", "b", 4),
            rail("bc", "b", "c", 6),
            rail("ac", "a", "c", 5),
            rail("ad", "a", "d", 20),
            rail("de", "d", "e", 2),
        ],
        4,
    )
    .unwrap();
    let request = query("a", "c", 3);
    network.set_availability("ac", false, 10).unwrap();
    network.set_availability("ad", false, 10).unwrap();
    let route = network.route(&request).unwrap();
    assert_eq!(
        (
            route.travel_minutes,
            route.cost_units,
            route.capacity_units,
            route.risk_points
        ),
        (10, 6, Some(10), 4)
    );
    network.set_availability("de", false, 10).unwrap();
    network.set_availability("ad", true, 10).unwrap();
    network.set_availability("ac", true, 2).unwrap();
    assert_eq!(network.cache.len(), 1);
    network.set_availability("ac", true, 3).unwrap();
    assert!(network.cache.is_empty());
    let shortcut = network.route(&request).unwrap();
    assert_eq!(
        (
            &*shortcut.legs[0].segment_id,
            shortcut.travel_minutes,
            shortcut.capacity_units
        ),
        ("ac", 5, Some(3))
    );
    network.set_availability("ac", true, 4).unwrap();
    let reverse = network.route(&query("c", "a", 4)).unwrap();
    assert_eq!(reverse.legs[0].from, "c");
    assert_eq!(reverse.legs[0].to, "a");
    assert_eq!(reverse.capacity_units, Some(4));
    assert_eq!(
        network.route(&request).unwrap().legs[0]
            .profile
            .capacity_units,
        4
    );
    assert!(network.set_availability("ac", true, 11).is_err());
    assert_eq!(network.availability("ac").unwrap().capacity_units, 4);
}

#[test]
fn failed_queries_follow_capacity_closure_direction_and_allowed_modes() {
    let mut road = rail("road", "a", "b", 1);
    road.mode = TransportMode::Road;
    road.bidirectional = false;
    let mut network = TransportNetwork::new(
        ["a", "b", "c"].map(city).to_vec(),
        vec![road, rail("rail", "b", "c", 1)],
        8,
    )
    .unwrap();
    let request = query("a", "c", 5);
    let rail_only = TransportRequest {
        allowed_modes: ModeSet::only(TransportMode::Rail),
        ..request.clone()
    };
    assert_eq!(network.route(&rail_only), Err(RouteError::Unreachable));
    assert_eq!(
        network.route(&query("c", "a", 1)),
        Err(RouteError::Unreachable)
    );
    network.set_availability("road", true, 2).unwrap();
    network.set_availability("rail", false, 10).unwrap();
    assert_eq!(network.route(&request), Err(RouteError::Disrupted));
    network.set_availability("rail", true, 10).unwrap();
    assert_eq!(
        network.route(&request),
        Err(RouteError::InsufficientCapacity { required_units: 5 })
    );
    network.set_availability("road", false, 2).unwrap();
    assert_eq!(network.route(&request), Err(RouteError::Disrupted));
    network.set_availability("road", true, 5).unwrap();
    let route = network.route(&request).unwrap();
    assert_eq!(
        route.legs.iter().map(|leg| leg.mode).collect::<Vec<_>>(),
        [TransportMode::Road, TransportMode::Rail]
    );
    assert_eq!(
        network.route(&query("a", "missing", 1)),
        Err(RouteError::UnknownEndpoint("missing".into()))
    );
    assert_eq!(
        network.route(&query("a", "c", 0)),
        Err(RouteError::InvalidDemand)
    );
}

#[test]
fn only_city_port_transfers_join_shipping_to_land() {
    let port = TransportNode {
        id: "port".into(),
        kind: NodeKind::Port,
    };
    let pier = TransportNode {
        id: "pier".into(),
        kind: NodeKind::Port,
    };
    let nodes = vec![city("city"), port, pier];
    for (mode, from, to) in [
        (TransportMode::PortTransfer, "port", "pier"),
        (TransportMode::Shipping, "city", "port"),
        (TransportMode::Road, "city", "port"),
    ] {
        let segment = TransportSegment {
            mode,
            ..rail("bad", from, to, 1)
        };
        assert!(TransportNetwork::new(nodes.clone(), vec![segment], 0).is_err());
    }
    let transfer = TransportSegment {
        mode: TransportMode::PortTransfer,
        prototype_only: true,
        ..rail("transfer", "city", "port", 15)
    };
    let ship = TransportSegment {
        mode: TransportMode::Shipping,
        ..rail("ship", "port", "pier", 90)
    };
    let mut network = TransportNetwork::new(nodes, vec![ship, transfer], 0).unwrap();
    let route = network.route(&query("pier", "city", 1)).unwrap();
    assert_eq!(
        route
            .legs
            .iter()
            .map(|leg| (leg.mode, leg.prototype_only))
            .collect::<Vec<_>>(),
        [
            (TransportMode::Shipping, false),
            (TransportMode::PortTransfer, true)
        ]
    );
    let mut start = GameClock::default();
    start.advance_minutes(23 * 60).unwrap();
    let arrival = route.arrival_clock(start).unwrap();
    assert_eq!(arrival.snapshot().total_minutes, 24 * 60 + 45);
    assert_eq!(start.snapshot().total_minutes, 23 * 60);
    assert!(network.cache.is_empty());
}

#[test]
fn local_queries_have_no_bottleneck_and_cache_stays_bounded() {
    let mut network =
        TransportNetwork::new(vec![city("a"), city("b")], vec![rail("ab", "a", "b", 4)], 1)
            .unwrap();
    let local = network.route(&query("a", "a", 1)).unwrap();
    assert!(local.legs.is_empty());
    assert_eq!(
        (
            local.travel_minutes,
            local.cost_units,
            local.capacity_units,
            local.risk_points
        ),
        (0, 0, None, 0)
    );
    network.route(&query("a", "b", 1)).unwrap();
    assert_eq!(network.cache.len(), 1);
    network.set_availability("ab", false, 10).unwrap();
    assert!(network.cache.is_empty());
}

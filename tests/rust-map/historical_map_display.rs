use super::*;

#[test]
fn historical_map_display_and_pick() {
    let root=Path::new(env!("CARGO_MANIFEST_DIR")).join("../data");
    let world=World::open(&root.join("world.json")).unwrap();
    let visuals=crate::politics::PoliticalVisuals::open(&root,&world).unwrap();
    let visual_json:serde_json::Value=serde_json::from_reader(File::open(root.join("political-flags.json")).unwrap()).unwrap();
    let cases=[
        ([30.3,-18.8],"map_authority:gw_552"),
        ([31.4,-12.],"map_authority:gw_5518"),
        ([24.,-14.],"map_authority:gw_5519"),
        ([40.8,23.],"political_map_region:hejaz"),
        ([44.2,24.5],"political_map_region:rashidi"),
        ([49.6,25.],"political_map_region:hasa"),
        ([56.,20.],"political_map_region:oman"),
        ([38.,19.],""),
    ];
    let mut pages=HashMap::new();
    for (point,expected) in cases {
        let regional=world.tiles.iter().rposition(|tile|tile.level>0&&crate::camera::inside(point,tile.core)).unwrap();
        for index in [0,regional] {
            let tile=&world.tiles[index];
            let pixels=pages.entry(index).or_insert_with(||Pixels::read(&root,tile).unwrap());
            let at=tile.offset_of(point);
            let owner=if pixels.terrain[at*4+2]>=192 {0} else {pixels.ids[at*2]};
            if expected.is_empty() {assert_eq!(owner,0,"{point:?} {}",tile.path);continue;}
            let entry=usize::from(owner.checked_sub(1).expect(expected));
            let polity=&world.polities[entry];
            assert!(polity.display_only);
            assert_eq!(polity.map_id(),expected);
            for date in ["1900-01-01","1900-01-28","1900-01-29","1900-03-12"] {
                assert!(polity.active(date),"{expected} {date}");
                assert!(visuals.record(entry).active(date),"{expected} missing material on {date}");
            }
            assert!(!polity.active("1899-12-31"));
            assert!(!polity.active("1901-01-01"));
            if expected.starts_with("map_authority:") {
                let visual=&visual_json["polities"][entry];
                assert_eq!(visual["visual"],"bsac_company_1893");
                assert_eq!(visual["role"],"COMPANY_FLAG");
                let geometry=expected.strip_prefix("map_authority:").unwrap();
                assert_eq!(polity.geometry_feature_id,geometry);
                assert_eq!((&*polity.from_date,&*polity.to_date),("1900-01-01","1901-01-01"));
                assert_eq!(world.polities.iter().filter(|row|row.geometry_feature_id==geometry).count(),1);
            }
        }
    }
}

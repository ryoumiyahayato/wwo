// Shared between the city footprint mips and the building meshes.
fn city_roof(paris: bool) -> vec3f {
    return select(vec3f(.369,.343,.320),vec3f(.387,.423,.467),paris);
}

fn city_wall(paris: bool) -> vec3f {
    return select(vec3f(.562,.453,.376),vec3f(.691,.655,.590),paris);
}

fn city_road(paris: bool, main: f32) -> vec3f {
    let local = select(vec3f(.565,.548,.519),vec3f(.590,.582,.562),paris);
    let arterial = select(vec3f(.483,.478,.468),vec3f(.506,.514,.517),paris);
    return mix(local,arterial,main);
}

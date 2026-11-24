//! Household and labour scenarios for areas with incomplete opening evidence.
//! Shares are conditional model parameters. Historical observations stay in their source classifications.
use super::Population;

#[derive(Clone, Copy, Debug, Eq, Ord, PartialEq, PartialOrd)]
pub(super) enum Region {
    Atlantic, Continental, Mediterranean, NorthAmerica, EastAsia,
    NorthChina, SouthChina, SouthAsia, TropicalAsia, LatinAmerica, NorthAfrica, SouthernAfrica, Other,
}

impl Region {
    pub(super) fn at(root: &str, pool: &str) -> Self {
        use Region::*;
        match root {
            "united_states_1900" | "dominion_of_canada" | "colony_of_newfoundland" => NorthAmerica,
            "british_isles_1900" | "country_fra" | "kingdom_of_belgium" | "kingdom_of_netherlands" |
            "kingdom_of_luxembourg" | "australia_colonies_1900" | "cshapes_gw_920" | "cshapes_gw_950" => Atlantic,
            "russian_empire" | "german_empire" | "austria_hungary" | "sweden_norway_union" |
            "kingdom_of_denmark" | "swiss_confederation" | "kingdom_of_romania" |
            "principality_of_bulgaria" | "kingdom_of_serbia" | "iceland_under_denmark" => Continental,
            "kingdom_of_italy" | "kingdom_of_spain" | "kingdom_of_portugal" | "kingdom_of_greece" => Mediterranean,
            "empire_of_japan" | "korean_empire" | "taiwan_under_japan" => EastAsia,
            "qing_empire" if ["zhili", "shandong", "shanxi", "henan", "shaanxi", "gansu", "fengtian",
                "jilin", "heilongjiang", "rehe", "xinjiang", "suiyuan", "mongolia"].iter().any(|p| pool.contains(p)) => NorthChina,
            "qing_empire" => SouthChina,
            "cshapes_gw_750" | "cshapes_gw_780" | "cshapes_gw_770" | "cshapes_gw_790" => SouthAsia,
            "cshapes_gw_850" | "cshapes_gw_840" | "cshapes_gw_811" | "cshapes_gw_800" => TropicalAsia,
            "brazil_1900" | "mexican_republic" | "argentina_1900" | "republic_of_colombia_1900" |
            "chile_1900" | "peru_1900" | "cuba_occupation_1900" | "uruguay_1900" | "bolivia_1900" => LatinAmerica,
            "khedivate_of_egypt" | "ottoman_empire" | "beylicate_of_tunis" | "cshapes_gw_580" => NorthAfrica,
            "cshapes_gw_561" | "cshapes_gw_562" | "cshapes_gw_590" | "cshapes_gw_585" => SouthernAfrica,
            _ => Other,
        }
    }

    pub(super) fn age_analogue(self, urban: bool) -> Option<&'static str> {
        use Region::*;
        Some(match (self, urban) {
            (NorthAmerica, _) => "us_state_new_york",
            (Atlantic, _) => "administrative_region:france_ain",
            (Continental, _) => "administrative_region:germany_preussen",
            (Mediterranean, _) => "administrative_region:france_ain",
            (EastAsia, true) => "jp_otsu_pref_tokyo",
            (EastAsia, false) => "jp_otsu_pref_tottori",
            (NorthChina | SouthChina, _) => "qing_hist_anhui",
            (SouthAsia, _) => "raj_agra_agra",
            (TropicalAsia, _) => "java_madoera_bantam",
            (LatinAmerica, _) => "mx_mexico",
            (NorthAfrica, true) => "egy_madina_cairo",
            (NorthAfrica, false) => "egy_markaz_abu_hummus",
            (SouthernAfrica, _) => "cshapes_gw_561",
            (Other, _) => return None,
        })
    }

    /// Share of the staple energy budget, in bread, flour, rice, maize, potatoes and rye.
    pub(super) fn staples(self) -> [f64; 6] {
        use Region::*;
        match self {
            Atlantic       => [0.68, 0.06, 0.02, 0.02, 0.19, 0.03],
            Continental    => [0.54, 0.09, 0.01, 0.02, 0.24, 0.10],
            Mediterranean  => [0.59, 0.19, 0.03, 0.10, 0.08, 0.01],
            NorthAmerica   => [0.45, 0.13, 0.02, 0.23, 0.14, 0.03],
            EastAsia       => [0.04, 0.10, 0.70, 0.07, 0.07, 0.02],
            NorthChina     => [0.02, 0.49, 0.15, 0.25, 0.07, 0.02],
            SouthChina     => [0.01, 0.14, 0.65, 0.13, 0.07, 0.00],
            SouthAsia      => [0.01, 0.28, 0.50, 0.17, 0.04, 0.00],
            TropicalAsia   => [0.01, 0.04, 0.75, 0.14, 0.06, 0.00],
            LatinAmerica   => [0.13, 0.14, 0.13, 0.45, 0.14, 0.01],
            NorthAfrica    => [0.40, 0.27, 0.09, 0.21, 0.03, 0.00],
            SouthernAfrica => [0.15, 0.16, 0.03, 0.57, 0.08, 0.01],
            Other          => [0.18, 0.19, 0.26, 0.25, 0.11, 0.01],
        }
    }

    /// Heating degree and marketed fuel proxies. None of these values are census observations.
    pub(super) fn fuel(self) -> (f64, f64) {
        use Region::*;
        match self {
            Continental | NorthChina => (1.75, 0.48),
            Atlantic | NorthAmerica => (1.28, 0.62),
            EastAsia => (0.92, 0.26),
            Mediterranean | SouthernAfrica => (0.65, 0.27),
            NorthAfrica | SouthChina => (0.43, 0.13),
            SouthAsia | TropicalAsia => (0.20, 0.11),
            LatinAmerica | Other => (0.48, 0.16),
        }
    }

    /// Agriculture, extractive trades, manufacturing, transport and other services.
    pub(super) fn sectors(self, urban: bool) -> [u64; 5] {
        use Region::*;
        if urban { return [5, 2, 35, 13, 45]; }
        match self {
            Atlantic | Continental | NorthAmerica => [49, 5, 24, 7, 15],
            EastAsia | Mediterranean => [63, 3, 17, 4, 13],
            LatinAmerica | SouthernAfrica => [67, 6, 12, 4, 11],
            _ => [77, 2, 10, 3, 8],
        }
    }
}

impl Population {
    pub(super) fn household_profile(&self, pool: &str) -> (Region, bool) {
        let opening = self.opening.as_ref();
        let part = opening.and_then(|opening| opening.partitions.get(pool));
        let aggregate = opening.and_then(|opening| opening.statistical_aggregates.get(pool));
        let root = part.map(|part| part.parent.as_str())
            .or_else(|| aggregate.map(|area| area.parent.as_str())).unwrap_or(pool);
        (Region::at(root, pool), part.is_some_and(|part| part.urban_municipality))
    }
}

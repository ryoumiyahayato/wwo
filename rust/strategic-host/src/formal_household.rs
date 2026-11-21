use crate::formal_save::invalid;
use serde::{Deserialize, Serialize};
use std::{
    collections::{BTreeMap, BTreeSet},
    io,
};

const ID_PREFIX: &str = "household:";

/// The members keep their ownership and accounts. The agreement permits
/// sharing personal staple stock left after each member's own daily need.
#[derive(Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub struct Household {
    pub home: String,
    pub formed_minute: i64,
    pub members: BTreeSet<String>,
}

#[derive(Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub struct HouseholdInvitation {
    pub inviter: String,
    pub home: String,
    pub minute: i64,
    existing_household: Option<String>,
}

#[derive(Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub(crate) struct Households {
    next_id: u64,
    households: BTreeMap<String, Household>,
    invitations: BTreeMap<String, HouseholdInvitation>,
}

impl Default for Households {
    fn default() -> Self {
        Self {
            next_id: 1,
            households: BTreeMap::new(),
            invitations: BTreeMap::new(),
        }
    }
}

impl Households {
    pub(crate) fn household_of(&self, person: &str) -> Option<(&str, &Household)> {
        self.households.iter().find_map(|(id, household)| {
            household
                .members
                .contains(person)
                .then_some((id.as_str(), household))
        })
    }

    pub(crate) fn invitation_for(&self, person: &str) -> Option<&HouseholdInvitation> {
        self.invitations.get(person)
    }

    /// Call with the actor's authorized request after resolving named identities,
    /// prior acquaintance, and presence at the proposed home.
    pub(crate) fn invite(
        &mut self,
        inviter: &str,
        invitee: &str,
        home: &str,
        minute: i64,
    ) -> io::Result<()> {
        if !person_id(inviter)
            || !person_id(invitee)
            || inviter == invitee
            || !home.strip_prefix("place:").is_some_and(|id| !id.is_empty())
            || minute < 0
            || self.household_of(invitee).is_some()
            || self.invitations.contains_key(invitee)
        {
            return Err(invalid("invalid household invitation"));
        }
        let existing_household = match self.household_of(inviter) {
            Some((id, household))
                if household.home == home && household.formed_minute <= minute =>
            {
                Some(id.to_owned())
            }
            Some(_) => {
                return Err(invalid(
                    "invitation does not match the household home and time",
                ))
            }
            None => None,
        };
        self.invitations.insert(
            invitee.to_owned(),
            HouseholdInvitation {
                inviter: inviter.to_owned(),
                home: home.to_owned(),
                minute,
                existing_household,
            },
        );
        Ok(())
    }

    /// The invitee alone accepts. The host checks both people are still present.
    pub(crate) fn accept(
        &mut self,
        invitee: &str,
        inviter: &str,
        home: &str,
        minute: i64,
    ) -> io::Result<String> {
        let invitation = self
            .invitation_for(invitee)
            .filter(|invitation| {
                invitation.inviter == inviter
                    && invitation.home == home
                    && invitation.minute <= minute
                    && self.invitation_matches(invitee, invitation)
            })
            .ok_or_else(|| invalid("no current household invitation for these people and home"))?;

        let id = if let Some(id) = invitation.existing_household.clone() {
            self.households
                .get_mut(&id)
                .expect("verified household invitation")
                .members
                .insert(invitee.to_owned());
            id
        } else {
            let next_id = self
                .next_id
                .checked_add(1)
                .ok_or_else(|| invalid("household ID exhausted"))?;
            let id = format!("{ID_PREFIX}{}", self.next_id);
            let household = Household {
                home: home.to_owned(),
                formed_minute: minute,
                members: BTreeSet::from([inviter.to_owned(), invitee.to_owned()]),
            };
            self.households.insert(id.clone(), household);
            self.next_id = next_id;
            id
        };
        self.remove_outdated_invitations(inviter, invitee);
        Ok(id)
    }

    pub(crate) fn decline(&mut self, invitee: &str, inviter: &str) -> bool {
        if !self
            .invitation_for(invitee)
            .is_some_and(|invitation| invitation.inviter == inviter)
        {
            return false;
        }
        self.invitations.remove(invitee);
        true
    }

    /// Named population calls this for a death; a living member can also leave.
    pub(crate) fn leave(&mut self, person: &str) -> bool {
        self.invitations
            .retain(|invitee, invitation| invitee != person && invitation.inviter != person);
        let Some((id, _)) = self.household_of(person) else {
            return false;
        };
        let id = id.to_owned();
        let household = self.households.get_mut(&id).expect("known household");
        household.members.remove(person);
        if household.members.len() < 2 {
            self.households.remove(&id);
            self.invitations.retain(|_, invitation| {
                invitation.existing_household.as_deref() != Some(id.as_str())
            });
        }
        true
    }

    /// This selects eligible donors. The stock owner checks actual surplus and
    /// executes FIFO consumption from the donor when allocating a shared meal.
    pub(crate) fn food_donors<'a, 'place>(
        &'a self,
        recipient: &str,
        current_place: impl Fn(&str) -> Option<&'place str>,
    ) -> Vec<&'a str> {
        let Some((_, household)) = self.household_of(recipient) else {
            return Vec::new();
        };
        let home = Some(household.home.as_str());
        if current_place(recipient) != home {
            return Vec::new();
        }
        household
            .members
            .iter()
            .map(String::as_str)
            .filter(|&donor| donor != recipient && current_place(donor) == home)
            .collect()
    }

    pub(crate) fn validate(
        &self,
        minute: i64,
        person_is_live: impl Fn(&str) -> bool,
        place_exists: impl Fn(&str) -> bool,
    ) -> bool {
        let mut seen_members = BTreeSet::new();
        self.next_id > 0
            && self.households.iter().all(|(id, household)| {
                id.strip_prefix(ID_PREFIX)
                    .and_then(|id| id.parse::<u64>().ok())
                    .is_some_and(|sequence| {
                        (1..self.next_id).contains(&sequence)
                            && format!("{ID_PREFIX}{sequence}") == *id
                    })
                    && (0..=minute).contains(&household.formed_minute)
                    && place_exists(&household.home)
                    && household.members.len() >= 2
                    && household
                        .members
                        .iter()
                        .all(|person| person_is_live(person) && seen_members.insert(person))
            })
            && self.invitations.iter().all(|(invitee, invitation)| {
                (0..=minute).contains(&invitation.minute)
                    && place_exists(&invitation.home)
                    && person_is_live(invitee)
                    && person_is_live(&invitation.inviter)
                    && self.invitation_matches(invitee, invitation)
            })
    }

    fn invitation_matches(&self, invitee: &str, invitation: &HouseholdInvitation) -> bool {
        invitee != invitation.inviter
            && self.household_of(invitee).is_none()
            && match self.household_of(&invitation.inviter) {
                Some((id, household)) => {
                    invitation.existing_household.as_deref() == Some(id)
                        && invitation.home == household.home
                        && invitation.minute >= household.formed_minute
                }
                None => invitation.existing_household.is_none(),
            }
    }

    fn remove_outdated_invitations(&mut self, inviter: &str, new_member: &str) {
        let current = self.household_of(inviter).map(|(id, _)| id.to_owned());
        self.invitations.retain(|invitee, invitation| {
            invitee != new_member
                && invitee != inviter
                && invitation.inviter != new_member
                && (invitation.inviter != inviter || invitation.existing_household == current)
        });
    }
}

fn person_id(id: &str) -> bool {
    id.strip_prefix("person:").is_some_and(|id| !id.is_empty())
}

#[cfg(test)]
mod tests {
    use super::*;

    const HOST: &str = "person:host";
    const GUEST: &str = "person:guest";
    const OTHER: &str = "person:other";
    const HOME: &str = "place:home";
    const AWAY: &str = "place:away";

    #[test]
    fn household_food_sharing_requires_accepted_current_household_and_presence() {
        let mut households = Households::default();
        households.invite(HOST, GUEST, HOME, 1).unwrap();
        assert!(households.accept(GUEST, OTHER, HOME, 2).is_err());
        assert!(households.accept(GUEST, HOST, AWAY, 2).is_err());
        assert!(households.food_donors(GUEST, |_| Some(HOME)).is_empty());
        let id = households.accept(GUEST, HOST, HOME, 2).unwrap();
        assert_eq!(households.household_of(GUEST).unwrap().0, id);
        assert_eq!(households.food_donors(GUEST, |_| Some(HOME)), vec![HOST]);
        assert!(households
            .food_donors(GUEST, |person| {
                Some(if person == HOST { AWAY } else { HOME })
            })
            .is_empty());

        households.invite(HOST, OTHER, HOME, 3).unwrap();
        let saved = serde_json::to_value(households).unwrap();
        let mut restored: Households = serde_json::from_value(saved).unwrap();
        let live = |person: &str| [HOST, GUEST, OTHER].contains(&person);
        assert!(restored.validate(3, live, |place| place == HOME));
        assert!(!restored.validate(3, |person| person == HOST, |place| place == HOME));
        assert!(restored.leave(GUEST));
        assert!(restored.household_of(HOST).is_none());
        assert!(restored.invitation_for(OTHER).is_none());
    }
}

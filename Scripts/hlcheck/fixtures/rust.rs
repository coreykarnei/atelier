//! Fixture: the constructs a Rust theme must tell apart.
use std::collections::HashMap;
use std::fmt::{self, Display};
mod util;
extern crate serde;

const MAX_RETRIES: u32 = 3;
static NAME: &str = "atelier";

/// A player with hit points.
#[derive(Debug, Clone)]
pub struct Player<'a, T: Display> {
    name: &'a str,
    hp: i32,
    tag: Option<T>,
}

enum Outcome {
    Hit(u32),
    Miss,
}

impl<'a, T: Display> Player<'a, T> {
    pub fn new(name: &'a str) -> Self {
        Player { name, hp: 10, tag: None }
    }

    fn heal(&mut self, amount: i32) -> i32 {
        self.hp += amount;
        self.hp
    }
}

impl fmt::Display for Outcome {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Outcome::Hit(n) if *n > 0 => write!(f, "hit {n}"),
            Outcome::Hit(_) | Outcome::Miss => write!(f, "miss"),
        }
    }
}

macro_rules! square {
    ($x:expr) => { $x * $x };
}

pub async fn roll(sides: u32) -> Result<u32, String> {
    if sides == 0 {
        return Err(String::from("sides"));
    }
    let mut total = 0u32;
    for i in 0..MAX_RETRIES {
        total += i;
    }
    while total > 100 { total -= 1; }
    'outer: loop { break 'outer; }
    let scores: Vec<_> = vec![1.5, 2.0].iter().map(|s| *s as u32).collect();
    let map: HashMap<&str, u32> = HashMap::new();
    let c = '\n';
    let ok = true && !false;
    let sum = square!(scores.len()) + map.len() as u32;
    println!("{} {sum} {:?}\t{}", NAME, scores, c);
    Ok(sum?)
}

fn main() {
    let p = Player::<&str>::new("Ada");
    drop(p);
}

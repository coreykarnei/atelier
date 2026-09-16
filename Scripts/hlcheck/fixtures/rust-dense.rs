#!/usr/bin/env rust-script
//! Crate-level doc comment: a dense fixture for the rust highlight query.
//! Every construct the query should colour appears at least once.

#![allow(dead_code, unused_variables)]

// A plain line comment.
/* A plain block comment. */
/** An outer block doc comment. */

use std::collections::HashMap;
use std::fmt::{self, Display, Formatter};
use std::io::{self as stdio, Read as _};
use std::sync::*;
pub use crate::shapes::Shape;
extern crate serde;

pub mod shapes;
mod inner {
    pub(crate) fn helper() -> u8 { super::MAX_RETRIES as u8 }
}

/// Number of retries before giving up.
pub const MAX_RETRIES: u32 = 3;
static GREETING: &str = "hello";
const PI_APPROX: f64 = 3.14159;

/// A point in 2-D space.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Point {
    pub x: f64,
    pub y: f64,
}

#[derive(Debug)]
pub struct Wrapper<'a, T: Display>(&'a T);

pub enum Color {
    Red,
    Green,
    Rgb(u8, u8, u8),
    Named { name: String, alpha: f32 },
}

pub trait Describe {
    fn describe(&self) -> String;
    fn kind(&self) -> &'static str {
        "thing"
    }
}

type Grid<T> = Vec<Vec<T>>;

union Bits {
    int: u32,
    float: f32,
}

impl Point {
    /// Constructs a new point.
    pub fn new(x: f64, y: f64) -> Self {
        Self { x, y }
    }

    pub const ORIGIN: Point = Point { x: 0.0, y: 0.0 };

    pub fn distance(&self, other: &Point) -> f64 {
        let dx = self.x - other.x;
        let dy = self.y - other.y;
        (dx * dx + dy * dy).sqrt()
    }

    pub fn translate(&mut self, dx: f64, dy: f64) {
        self.x += dx;
        self.y += dy;
    }

    fn scale<F>(self, mut factor: F) -> Point
    where
        F: FnMut(f64) -> f64,
    {
        Point::new(factor(self.x), factor(self.y))
    }
}

impl Describe for Point {
    fn describe(&self) -> String {
        format!("({}, {})", self.x, self.y)
    }
}

impl<'a, T: Display> Display for Wrapper<'a, T> {
    fn fmt(&self, f: &mut Formatter<'_>) -> fmt::Result {
        write!(f, "<{}>", self.0)
    }
}

macro_rules! square {
    ($x:expr) => {
        $x * $x
    };
    ($($x:expr),+ $(,)?) => {
        [$(square!($x)),+]
    };
}

#[inline]
#[cfg(not(target_os = "windows"))]
pub fn classify(color: &Color, threshold: u8, ref label: &str, _: i32) -> Option<&'static str> {
    match color {
        Color::Red | Color::Green => Some("primary"),
        Color::Rgb(r, g, b) if *r > threshold && *g == *b => Some("reddish"),
        Color::Rgb(..) => None,
        Color::Named { name, alpha: a } => {
            if a.is_nan() || name.is_empty() {
                return None;
            }
            Some("named")
        }
    }
}

async fn fetch(url: &str) -> Result<String, Box<dyn std::error::Error>> {
    let body = reqwest::get(url).await?.text().await?;
    Ok(body)
}

fn never_returns() -> ! {
    panic!("unreachable: {}", GREETING);
}

pub fn main() {
    let mut points: Vec<Point> = Vec::with_capacity(MAX_RETRIES as usize);
    let map: HashMap<&str, i64> = HashMap::new();
    let hex = 0xFF_u8;
    let bin = 0b1010;
    let oct = 0o777;
    let big = 1_000_000i64;
    let ratio = 2.5e-3_f32;
    let ch = 'x';
    let esc = '\n';
    let text = "tab\tnewline\n\u{1F600} \"quoted\" {}";
    let raw = r#"raw "string" with \no escapes"#;
    let bytes = b"bytes\x41";
    let flag = true && !false;

    for i in 0..MAX_RETRIES {
        points.push(Point::new(i as f64, -1.5));
    }

    'outer: loop {
        let mut n = 0u32;
        while n < 10 {
            n += 1;
            if n % 2 == 0 {
                continue;
            } else if n >= 7 {
                break 'outer;
            }
        }
    }

    let total: f64 = points.iter().map(|p| p.x).sum();
    let doubled = points.iter().map(|&Point { x, y }| x * 2.0 + y).collect::<Vec<_>>();
    let add = |a: i32, b: i32| -> i32 { a + b };
    let shifted = (hex as u32) << 2 | 1 >> 1 ^ 0xF & 0x3;
    let cmp = big != 0 && ratio <= 1.0 || total >= 0.0;

    let origin = Point::ORIGIN;
    let dist = origin.distance(&points[0]);
    let described = origin.describe();
    let color = Color::Named { name: String::from("teal"), alpha: 0.5 };
    let (first, ..) = (1, 2, 3);
    let [head, rest @ ..] = [1, 2, 3];
    let boxed: Box<dyn Describe> = Box::new(origin);

    if let Some(kind) = classify(&color, 128, "lbl", 0) {
        println!("{kind}: {:.2} {}", dist, described);
    } else {
        eprintln!("none");
    }

    let wrapped = Wrapper(&total);
    drop(wrapped);
    let size = std::mem::size_of::<Point>();
    let squared = square!(3, 4);
    assert_eq!(add(1, 2), 3);
    let result: Result<i32, fmt::Error> = Err(fmt::Error);
    unsafe {
        let bits = Bits { int: 1 };
        let _ = bits.float;
    }
    let value = match result {
        Ok(v) => v,
        Err(e) => {
            dbg!(e);
            -1
        }
    };
    let ptr = &mut points as *mut Vec<Point>;
    let label = shapes::area(1.0) + stdio::stdin().bytes().count() as f64;
    let sum = points.iter().fold(0.0, |acc, p| acc + p.y);
    return;
}

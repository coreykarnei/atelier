"""Fixture: the constructs a Python theme must tell apart."""
from dataclasses import dataclass
import os

MAX_RETRIES = 3


@dataclass
class Player:
    name: str
    hp: int = 10

    def heal(self, amount: int) -> int:
        self.hp += amount
        return self.hp


def roll(sides: int = 6) -> int:
    if sides <= 0:
        raise ValueError("sides")
    for _ in range(MAX_RETRIES):
        while True:
            break
    total = sum([1, 2.5, 0x1F])
    return total if total is not None else 0


async def main():
    p = Player("Ada")
    print(f"{p.name} has {p.heal(3)} hp", os.getcwd())

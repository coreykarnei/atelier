// Line comment: imports, type-only imports, namespaces
import fs, { readFile as read } from "node:fs";
import type { Stats } from "fs";
import * as path from "path";
import { type Dirent, mkdir } from "fs/promises";
export { helper as util } from "./util";
export type { Widget } from "./widget";
declare const GLOBAL_FLAG: boolean;
declare module "some-module" {
  export function decl(x: number): string;
}

/**
 * Doc comment on an interface.
 * @template T the item type
 */
export interface Container<T extends object = {}> extends Iterable<T> {
  readonly items: T[];
  size?: number;
  get(index: number): T | undefined;
  [key: string]: unknown;
  new (init: T[]): Container<T>;
}

type Callback<T, R = void> = (item: T, index: number) => R;
type Mapped<T> = { readonly [K in keyof T]?: T[K] extends Function ? never : T[K] };
type Union = "a" | "b" | 42 | true | null | `prefix-${string}`;
type Cond<T> = T extends string ? "str" : T extends number ? "num" : unknown;
type Fn = typeof compute;
type Tup = [first: string, second?: number, ...rest: boolean[]];

enum Color { Red = 1, Green, Blue = "blue".length }
const enum Direction { Up, Down }

namespace Geometry.Shapes {
  export const PI_ISH: number = 3.14;
  export abstract class Base {
    protected abstract area(): number;
  }
}

/* Block comment before a decorated class */
@Component({ selector: "app-shape" })
export default class Shape<T = unknown> extends Geometry.Shapes.Base implements Container<T> {
  static count: number = 0;
  #secret = 42;
  private readonly kind: string = "generic";
  public items: T[] = [];
  declare size?: number;
  [key: string]: unknown;

  @Input() name!: string;

  constructor(name: string, public sides: number = 3, ...rest: T[]) {
    super();
    this.name = name;
    Shape.count++;
  }

  get label(): string {
    return this.kind;
  }

  set label(value: string) {
    (this as any).kind = value;
  }

  protected override area(): number {
    return this.#secret * this.sides;
  }

  get(index: number): T | undefined {
    return this.items[index];
  }

  static create<U>(this: void, ...args: U[]): Shape<U> {
    return new Shape<U>("s", 4, ...args);
  }

  async *walk(step: number): AsyncGenerator<number> {
    for (let i = 0; i < this.sides; i++) {
      yield await Promise.resolve(i * step);
    }
  }

  [Symbol.iterator](): Iterator<T> {
    return this.items[Symbol.iterator]();
  }
}

function compute<T extends number>(a: T, b: number = 10, { x, y: why }: { x: number; y: number }, [first, ...others]: number[]): number {
  const MAX_ITEMS = 100 as const;
  let total: number = a + b - x * why / first % 2 ** 3;
  total += others.length;
  total = total >>> 2 | (total & 0xff) ^ ~0;
  if (total > MAX_ITEMS && !Number.isNaN(total) || total === -1) {
    total = MAX_ITEMS;
  } else if (total !== 0 && a instanceof Object) {
    total = typeof a === "number" ? a : parseInt("12", 10);
  } else {
    total = (null ?? undefined) as unknown as number;
  }
  return total satisfies number;
}

const arrow = <T,>(n: T): T[] => [n];
const obj: Record<string, unknown> = {
  method(): number { return 1; },
  handler: function (evt: Event): Event { return evt; },
  onClick: (e: MouseEvent) => e.target,
  [Symbol.iterator]: null,
};
outer: for (const key in obj) {
  while (true) {
    do { break outer; } while (false);
  }
}
for (const item of [1, 2, 3]) {
  switch (item) {
    case 1:
      continue;
    case 2:
      break;
    default:
      console.log(item);
  }
}
try {
  JSON.parse("{}");
  throw new TypeError("bad");
} catch (err: unknown) {
  console.error((err as Error).message);
} finally {
  delete obj.arrow;
  void 0;
}

const nums: number[] = [0, 1.5, 1e10, 0x1F, 0o17, 0b1010, .5, NaN, Infinity];
const big: bigint = 123n;
const str = 'single \'quoted\' \n A';
const tpl = `template ${compute(1, 2, { x: 1, y: 2 }, [1])} and ${obj.arrow} \t`;
const re = /ab+c\d/gi;
const chained = obj?.method?.() ?? Math.max(1, 2);
const maybe = document.querySelector<HTMLDivElement>("div")!;
const assertion = <string>str;
let maybeFn: ((x: number) => void) | null = null;
function isString(v: unknown): v is string { return typeof v === "string"; }
function assertIt(v: unknown): asserts v is string {}
function overload(x: string): string;
function overload(x: number): number;
function overload(x: any): any { return x; }
abstract class Animal { abstract speak(): void; }
export function* gen(): Generator<number> { yield 1; }
const keys = Object.keys(obj) as Array<keyof typeof obj>;
let u: unique symbol;
type Infer<T> = T extends Promise<infer U> ? U : never;
type Acc = { get x(): number; set x(v: number) };

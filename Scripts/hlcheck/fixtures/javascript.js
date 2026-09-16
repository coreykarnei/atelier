#!/usr/bin/env node
"use strict";
// Line comment: imports and requires
import fs, { readFile as read } from "node:fs";
import * as path from "path";
import defaultExport from "./local.js";
export { helper as util } from "./util.js";
export * from "./reexport.js";
const os = require("os");

/**
 * Doc comment for a class.
 * @param {string} name
 */
export default class Shape extends Base {
  static count = 0;
  #secret = 42;
  kind = "generic";

  constructor(name, sides = 3, ...rest) {
    super(name);
    this.name = name;
    this.sides = sides;
    Shape.count++;
  }

  get area() {
    return this.#secret * this.sides;
  }

  set label(value) {
    this.kind = value;
  }

  static create(...args) {
    return new Shape(...args);
  }

  async *walk(step) {
    for (let i = 0; i < this.sides; i++) {
      yield await Promise.resolve(i * step);
    }
  }

  describe() {
    return `Shape ${this.name} with ${this.sides} sides\n`;
  }
}

/* Block comment before a free function */
function compute(a, b = 10, { x, y: why }, [first, ...others]) {
  const MAX_ITEMS = 100;
  let total = a + b - x * why / first % 2 ** 3;
  total += others.length;
  total <<= 1;
  total = total >>> 2 | (total & 0xff) ^ ~0;
  if (total > MAX_ITEMS && !Number.isNaN(total) || total === -1) {
    total = MAX_ITEMS;
  } else if (total !== 0 && a instanceof Object) {
    total = typeof a === "number" ? a : parseInt("12", 10);
  } else {
    total = null ?? undefined;
  }
  return total;
}

const arrow = (n) => n * 2;
const obj = {
  method() { return 1; },
  handler: function (evt) { return evt; },
  onClick: (e) => e.target,
  MAX_ITEMS,
  arrow,
  [Symbol.iterator]: null,
};
obj.later = async function () { await delay(1); };
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
} catch (err) {
  console.error(err.message);
} finally {
  delete obj.arrow;
  void 0;
}

const nums = [0, 1.5, 1e10, 0x1F, 0o17, 0b1010, 123n, .5, NaN, Infinity];
const str = 'single \'quoted\' \n A \x41';
const tpl = `template ${compute(1, 2)} and ${obj.arrow(3)} \t`;
const re = /ab+c\d/gi;
const label = true && false || null;
const chained = obj?.method?.() ?? Math.max(1, 2);
const [aa, bb = 2] = nums;
const { x: xx, y = 1, ...restProps } = obj;
const isFinite2 = isFinite(1), enc = encodeURIComponent("a b");
window.document.title = String(new Date().getTime());
export const html = html`<div>${str}</div>`;
export function* gen() { yield 1; }

---
title: Highlight fixture
tags: [markdown, atelier]
---

# Heading one

## Heading two

### Heading three

#### Heading four

##### Heading five

###### Heading six

Setext heading one
==================

Setext heading two
------------------

A paragraph with *emphasis*, _also emphasis_, **strong**, __also strong__,
***both at once***, ~~strikethrough~~, and `inline code` with a `second span`.
Escapes: \*not emphasis\* and \# not a heading. Hard break at the end of this line\
continues here. Entities: &amp; &nbsp; &copy; and a bare autolink <https://example.com>
plus an email autolink <mail@example.com>.

Links: [inline link](https://example.com/path "with a title"),
[reference link][ref], [collapsed][], [shortcut], and an
![image alt text](https://example.com/cat.png "Cat"). Inline <span class="x">html</span> here.

[ref]: https://example.com/reference "Reference title"
[collapsed]: <https://example.com/collapsed>
[shortcut]: /relative/path

- Unordered item with `code`
- Another item
  - Nested item
    continued on the next line
+ Plus marker
* Star marker

1. Ordered item
2. Second ordered item
   1. Nested ordered
3) Parenthesis marker

- [ ] Unchecked task
- [x] Checked task

> A block quote with **strong** text
> spanning two lines.
>
> > Nested quote.

---

***

___

```swift
// A fenced code block with an info string
let answer: Int = 42
print("hello \(answer)")
```

~~~
Tilde fence without a language.
~~~

    An indented code block
    on two lines.

| Column A | Column B | Column C |
|:---------|:--------:|---------:|
| left     | center   | right    |
| `code`   | **bold** | [link](x) |

<div align="center">
  <b>An HTML block</b>
</div>

[comment]: # (A comment via link reference definition)

Final paragraph with trailing text.

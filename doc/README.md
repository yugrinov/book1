# Markdown Notes
The documentation team uses the tool [Bookbinder](https://github.com/greenplum-db/gpdb).  Bookbinder's rendering algorithm
differs from that of more renderers, such as that in VS Code.  This document contains a list of gotchas which may make
The Docs team's rendering of our documents more challenging.

Be careful in your documents:
- A blank line before code block is necessary to prevent Bookbinder from interpreting the first two back-ticks as a double-quote
- This is also true for tables
- Indent code blocks by four spaces; otherwise any leading "#" characters will cause numbered lists to reset to "1"
- The divider between table headers and the rows of the table need to match the widths of the header labels, but the
  rows do not.  E.g.:

```
  | String 1 | My String 2 | Three | Four |
  | -------- | ----------- | ----- | ---- |
  | Bleah | . | Supercalifragilisticexpialadocious | bar |
```

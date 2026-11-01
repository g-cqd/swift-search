# Queries

| Query | Finds |
| --- | --- |
| `shared` | Every declaration named `shared`. |
| `Client.shared`, `Outer.Inner.leaf` | A member whose enclosing types end with these. |
| `fetch(id:_:)`, `Client.fetch()` | A callable with exactly these argument labels. |
| `/load.*/` | Every declaration whose whole name the RE2 expression matches. |
| `s:3App6ClientC` | The declaration with this USR (needs `--index-store`). |

Regular expressions run on [AemiRegex](https://github.com/g-cqd/AemiRegex) in time linear in the name, so no query, from the command
line or from an MCP client, can make a search exponential.

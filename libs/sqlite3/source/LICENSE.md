# SQLite Third-Party Notice

Euclid includes SQLite 3.53.4 and its `spellfix1` extension in source form.
The following files originate from the SQLite project:

- `sqlite3.c`
- `sqlite3.h`
- `sqlite3ext.h`
- `shell.c`
- `spellfix.c`

The SQLite authors have dedicated this software to the public domain. The
authoritative SQLite copyright and public-domain statement is available at
<https://www.sqlite.org/copyright.html>.

SQLite source files carry the following notice:

> The author disclaims copyright to this source code. In place of a legal
> notice, here is a blessing:
>
> - May you do good and not evil.
> - May you find forgiveness for yourself and forgive others.
> - May you share freely, never taking more than you give.

`sqlite3_custom.c` is an Euclid integration wrapper, not an upstream SQLite
file. It is distributed under the license in Euclid's root `LICENSE` file.

#define SQLITE_ENABLE_FTS5 1
#define SQLITE_OMIT_LOAD_EXTENSION 1

#include "sqlite3.c"
#include "spellfix.c"

int euclid_sqlite_register_spellfix(sqlite3 *database) {
    return sqlite3_spellfix_init(database, NULL, NULL);
}

CREATE TABLE user_collection_note (
    collection_id BLOB NOT NULL CHECK (length(collection_id) = 16),
    entry_id BLOB NOT NULL CHECK (length(entry_id) = 16),
    note_text TEXT NOT NULL DEFAULT ''
        CHECK (length(CAST(note_text AS BLOB)) <= 4096
            AND instr(note_text, char(0)) = 0),
    notes_on_top INTEGER NOT NULL DEFAULT 0
        CHECK (notes_on_top IN (0, 1)),
    PRIMARY KEY (collection_id, entry_id)
) STRICT, WITHOUT ROWID;

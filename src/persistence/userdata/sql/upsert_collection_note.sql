INSERT INTO user_collection_note (
    collection_id, entry_id, note_text, notes_on_top
) VALUES (?1, ?2, ?3, ?4)
ON CONFLICT(collection_id, entry_id) DO UPDATE SET
    note_text = excluded.note_text,
    notes_on_top = excluded.notes_on_top;

SELECT note_text, notes_on_top
FROM user_collection_note
WHERE collection_id = ?1 AND entry_id = ?2;

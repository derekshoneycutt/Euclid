SELECT entry_id, collection_id, parent_entry_id, sibling_order, entry_kind, animation_id
FROM user_collection_entry
ORDER BY collection_id, parent_entry_id, sibling_order, entry_id;

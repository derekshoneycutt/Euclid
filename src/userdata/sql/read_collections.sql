SELECT collection_id, system_role, display_name, collection_order, is_read_only
FROM user_collection
ORDER BY collection_order, collection_id;

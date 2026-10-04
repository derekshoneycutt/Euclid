SELECT documents.source_namespace, documents.animation_id
FROM animation_search
JOIN animation_catalog AS documents ON documents.rowid = animation_search.rowid
WHERE animation_search MATCH ?1
ORDER BY bm25(animation_search, 10.0, 6.0, 8.0, 2.0) ASC,
documents.source_namespace ASC, documents.animation_id ASC
LIMIT ?2 OFFSET ?3

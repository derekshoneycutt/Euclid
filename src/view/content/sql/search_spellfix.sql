SELECT word, distance, rank FROM search_terms
WHERE word MATCH ?1 AND top = ?2
ORDER BY distance ASC, rank ASC, word ASC LIMIT ?3

-- Which model produced each embedding.
--
-- DEPLOY.md has warned since 0005 that embeddings from two providers are not
-- comparable: the vectors live in different spaces, so a nearest-neighbour
-- search across a mixed corpus returns rows ranked by nothing meaningful. It
-- was a paragraph in a document, and nothing enforced it.
--
-- That became urgent when the ingest learned to skip documents it had already
-- loaded. Skipping is right for resuming an interrupted run and exactly wrong
-- when the provider has changed underneath it — the documents it would skip are
-- precisely the ones carrying the old model's vectors. The safety feature and
-- the provider switch combine into a silently broken index.
--
-- Recording the model turns "do not mix providers" from advice into a fact the
-- ingest can check. A document is skipped only when its embeddings came from
-- the model about to be used; anything else is re-embedded.

alter table public.kb_documents
  add column if not exists embedding_model text;

-- Everything currently in the table was embedded by voyage-3: it is the only
-- provider that has ever run against this project, and the ingest defaults to
-- that model when VOYAGE_API_KEY is set. Recording it as fact rather than
-- leaving it null, so the first run after this migration can tell the
-- difference between "unknown" and "not yet embedded".
update public.kb_documents
   set embedding_model = 'voyage-3'
 where embedding_model is null
   and exists (select 1 from public.kb_chunks c where c.document_id = kb_documents.id);

comment on column public.kb_documents.embedding_model is
  'The model that produced this document''s chunk embeddings. Null means the '
  'document has no embeddings yet. A corpus containing more than one non-null '
  'value is broken for retrieval, whatever the row counts say — see '
  'kb_embedding_health.';

-- One row per model in the corpus. More than one row is the failure this
-- migration exists to make visible, and a count of documents alone would never
-- show it.
create or replace view public.kb_embedding_health
with (security_invoker = true) as
select
  coalesce(d.embedding_model, '(not embedded)') as embedding_model,
  count(distinct d.id) as documents,
  count(c.id) as chunks,
  count(c.id) filter (where c.embedding is null) as chunks_without_a_vector
from public.kb_documents d
left join public.kb_chunks c on c.document_id = d.id
group by coalesce(d.embedding_model, '(not embedded)')
order by documents desc;

comment on view public.kb_embedding_health is
  'Expect exactly one embedded model, and zero chunks_without_a_vector. Two '
  'embedded models means retrieval is comparing vectors from different spaces '
  'and the answers are ranked by noise; re-ingest everything on one provider.';

revoke all on public.kb_embedding_health from anon, authenticated;

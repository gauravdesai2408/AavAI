# AavAI standing development requirements

## EU and Danish readiness

The user requires all future product development to account for applicable EU
regulations and Danish requirements. Treat this as an ongoing design, implementation
and release constraint, not a final-stage paperwork task.

- Read `docs/eu-readiness.md` before product changes. It records known gaps,
  official sources and release gates; existing gaps are not approved exceptions.
- Use Denmark as the provisional business base. Do not infer legal establishment,
  launch markets or a final legal classification solely from founder residence.
- For each feature, assess changes to data collected, purpose, storage, retention,
  recipients, permissions, user controls and network access. Record material changes
  and unresolved risks in the readiness document.
- Default to on-device processing and data minimisation. Do not introduce content
  uploads, analytics, training on user data, background recording or new third-party
  data sharing without explicit scope approval and an applicable-law assessment.
- Protect audio, transcripts, dictionary and contextual text; exclude content from
  logs/telemetry. Test cancellation, secure-field blocking, deletion failure paths,
  retention and recovery whenever affected. Preserve existing user data in migrations.
- Keep optional collection/retention transparent and privacy-preserving. OS
  permissions, encryption and offline operation do not by themselves establish
  compliance or a lawful basis for every purpose.
- Assess dependencies and model licenses, download integrity, update security and
  vendor/system-service behavior. Do not equate EU hosting with GDPR compliance.
- Recheck current official EU/Danish sources when making regulatory decisions;
  do not rely on stored deadlines or summaries as permanently current law.
- Track relevant GDPR/Danish data-protection, ePrivacy, AI Act, Cyber Resilience
  Act and distribution obligations according to actual scope. Escalate unresolved
  legal classifications and country-specific launch questions for qualified review.
- Do not claim the product is certified, fully compliant, or ready for EU release
  without appropriate implementation, verification and operational/legal review.

## Delivery discipline

Preserve the working Mac baseline until native replacement gates pass. Keep model
weights, datasets and build artifacts out of Git. Do not claim Flow parity from
unit tests, installer size or small curated examples. See `docs/native-migration.md`
for implementation status and `docs/evaluation-protocol.md` for evaluation gates.
